import SwiftUI
import AVFoundation
import UIKit

struct CameraGuideView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = CameraGuideViewModel()
    @State private var cameraController = CameraSessionController()
    @State private var showPermissionAlert = false
    @State private var lastCapturedPreview: UIImage?
    @State private var subjectService = SubjectMaskingService()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreview(session: cameraController.session)
                .ignoresSafeArea()
                .accessibilityLabel("相机预览")
                .accessibilityHint("对准展品或展牌")

            VStack {
                Spacer()
                statusOverlay
                mockControls
                captureControls
            }
            .padding()
        }
        .navigationTitle("相机导览")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.updateExhibits(appState.exhibits)
            viewModel.checkAuthorization()
            viewModel.onExhibitGenerated = { exhibit in
                appState.upsertExhibit(exhibit)
                appState.addRecent(exhibit: exhibit)
            }
            configureCamera()
        }
        .onChange(of: viewModel.authorizationState) { _, state in
            if state == .authorized {
                cameraController.start()
                viewModel.startScanning()
            }
        }
        .sheet(isPresented: $viewModel.isSheetPresented) {
            if case let .recognized(exhibit) = viewModel.recognitionState {
                ExhibitSheetView(
                    exhibit: exhibit,
                    stage: viewModel.captureStage,
                    ocrSummary: viewModel.lastOCRSummary
                )
                    .presentationDetents([.height(180), .medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .alert("需要相机权限", isPresented: $showPermissionAlert) {
            Button("去设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("请在设置中允许相机访问，以便识别展品二维码或展牌文字。")
        }
        .onChange(of: viewModel.authorizationState) { _, state in
            if state == .denied {
                showPermissionAlert = true
            }
        }
    }

    private var statusOverlay: some View {
        VStack(spacing: 12) {
            if case .failed(let message) = viewModel.recognitionState {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(message)
                Button("重试") {
                    viewModel.reset()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("重试识别")
                .accessibilityHint("重新开始识别展品")
            } else {
                Text(stageHint)
                    .font(.callout)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(stageHint)
            }
        }
    }

    private func configureCamera() {
        cameraController.configure()
        cameraController.onQRCodeDetected = { code in
            Task { @MainActor in
                viewModel.handleQRCode(code)
            }
        }
        cameraController.onTextDetected = { text in
            Task { @MainActor in
                viewModel.handleRecognizedText(text)
            }
        }
        cameraController.onPhotoCaptured = { data in
            Task { @MainActor in
                lastCapturedPreview = UIImage(data: data)
                handlePhotoData(data)
            }
        }

        if viewModel.authorizationState == .notDetermined {
            Task {
                await viewModel.requestAccess()
            }
        }
    }

    private func handlePhotoData(_ data: Data) {
        switch viewModel.captureStage {
        case .signboard:
            viewModel.handleSignboardPhoto(data)
        case .artifact(let exhibit):
            Task {
                let inputImage = UIImage(data: data)
                let maskedImage = await subjectService.extractSubject(from: inputImage)
                let outputData = maskedImage?.pngData() ?? data

                if let url = appState.saveArtifactPhoto(data: outputData, exhibitId: exhibit.id) {
                    viewModel.handleArtifactPhoto(outputData, saveURL: url)
                    await appState.captureLocation(for: exhibit.id)
                } else {
                    viewModel.recognitionState = .failed("保存照片失败，请重试")
                }
            }
        case .done:
            break
        }
    }

    private var stageHint: String {
        switch viewModel.captureStage {
        case .signboard:
            return "拍摄展牌/文字以识别展品"
        case .artifact:
            return "拍摄文物主体以保存预览"
        case .done:
            return "已完成拍摄，可查看详情"
        }
    }

    private var captureControls: some View {
        VStack(spacing: 10) {
            Button {
                cameraController.capturePhoto()
            } label: {
                Label(captureButtonTitle, systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isProcessing)
            .accessibilityLabel("拍照识别")
            .accessibilityHint("拍摄展牌或文物主体")

            if let preview = lastCapturedPreview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("最近拍摄预览")
            }
        }
    }

    private var captureButtonTitle: String {
        if viewModel.isProcessing {
            return "识别中..."
        }
        switch viewModel.captureStage {
        case .signboard:
            return "拍展牌识别"
        case .artifact:
            return "拍文物主体"
        case .done:
            return "已完成拍摄"
        }
    }

    private var mockControls: some View {
        VStack(spacing: 8) {
            Button {
                guard let exhibit = appState.exhibits.randomElement() else { return }
                viewModel.simulateRecognition(exhibit)
            } label: {
                Label("模拟识别展品", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("模拟识别展品")
            .accessibilityHint("用于演示识别流程")
        }
    }
}

private struct ExhibitSheetView: View {
    @EnvironmentObject private var appState: AppState
    let exhibit: Exhibit
    let stage: CameraGuideViewModel.CaptureStage
    let ocrSummary: OCRSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule()
                .frame(width: 36, height: 4)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(exhibit.title)
                .font(.title3.weight(.semibold))

            Text(exhibit.shortIntro)
                .font(.body)
                .foregroundStyle(.secondary)

            if let summary = ocrSummary {
                VStack(alignment: .leading, spacing: 6) {
                    Text("识别摘要")
                        .font(.headline)
                    Text("标题：\(summary.title)")
                        .font(.subheadline)
                    if let date = summary.dateText {
                        Text("年代：\(date)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("简介：\(summary.intro)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            if case .artifact = stage {
                Label("下一步：拍摄文物主体照片", systemImage: "camera")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("下一步拍摄文物主体照片")
            }

            NavigationLink {
                ExhibitDetailView(exhibit: exhibit)
            } label: {
                Label("查看展品详情", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("查看展品详情")
            .accessibilityHint("进入展品详情页")

            Spacer()
        }
        .padding(20)
        .onAppear {
            appState.addRecent(exhibit: exhibit)
        }
    }
}
