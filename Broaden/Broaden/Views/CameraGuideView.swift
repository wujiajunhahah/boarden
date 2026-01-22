import SwiftUI
import AVFoundation
import UIKit
import PhotosUI

struct CameraGuideView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = CameraGuideViewModel()
    @State private var cameraController = CameraSessionController()
    @State private var showPermissionAlert = false
    @State private var lastCapturedPreview: UIImage?
    @State private var subjectService = SubjectMaskingService()

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isGalleryPresented = false

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
                Spacer()
                cameraControls
            }
            .padding(.bottom, 34)
        }
        .navigationBarHidden(true)
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
        .photosPicker(
            isPresented: $isGalleryPresented,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            handlePhotoPickerSelection(newItem)
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
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(message)
                Button("重试") {
                    viewModel.reset()
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .accessibilityLabel("重试识别")
                .accessibilityHint("重新开始识别展品")
            } else {
                Text(stageHint)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(stageHint)
            }
        }
        .padding(.top, 60)
    }

    private var cameraControls: some View {
        HStack(alignment: .center, spacing: 0) {
            // 左侧：相册按钮
            Button {
                isGalleryPresented = true
            } label: {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("相册")
            .accessibilityHint("从相册选择照片")

            Spacer()

            // 中间：拍照按钮
            Button {
                cameraController.capturePhoto()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 72, height: 72)

                    Circle()
                        .stroke(Color.black, lineWidth: 2)
                        .frame(width: 64, height: 64)

                    if viewModel.isProcessing {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 56, height: 56)
                    }
                }
            }
            .disabled(viewModel.isProcessing)
            .accessibilityLabel("拍照")
            .accessibilityHint("拍摄展牌或文物主体")

            Spacer()

            // 右侧：预览/跳过按钮
            if let preview = lastCapturedPreview {
                Button {
                    // 可以点击预览查看详情
                } label: {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .accessibilityLabel("最近拍摄")
            } else {
                Button {
                    // 跳过拍摄，直接进入详情
                    if let exhibit = appState.exhibits.first {
                        viewModel.recognitionState = .recognized(exhibit)
                        viewModel.isSheetPresented = true
                    }
                } label: {
                    Text("跳过")
                        .font(.callout)
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("跳过")
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.6), Color.black.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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

    private func handlePhotoPickerSelection(_ item: PhotosPickerItem?) {
        guard let item = item else { return }

        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    lastCapturedPreview = image
                    handlePhotoData(data)
                }
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
