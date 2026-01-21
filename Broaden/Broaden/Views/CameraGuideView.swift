import SwiftUI
import AVFoundation

struct CameraGuideView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = CameraGuideViewModel()
    @AppStorage("recognitionMode") private var recognitionModeRaw = RecognitionMode.qrOnly.rawValue

    @State private var cameraController = CameraSessionController()
    @State private var showPermissionAlert = false

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
            }
            .padding()
        }
        .navigationTitle("相机导览")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.updateExhibits(appState.exhibits)
            viewModel.checkAuthorization()
            configureCamera()
        }
        .onChange(of: viewModel.authorizationState) { _, state in
            if state == .authorized {
                cameraController.start()
                viewModel.startScanning()
            }
        }
        .onChange(of: recognitionModeRaw) { _, _ in
            cameraController.enableTextRecognition = recognitionMode == .qrAndText
        }
        .sheet(isPresented: $viewModel.isSheetPresented) {
            if case let .recognized(exhibit) = viewModel.recognitionState {
                ExhibitSheetView(exhibit: exhibit)
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
                Text("对准展品二维码或展牌")
                    .font(.callout)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("对准展品二维码或展牌")
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
        cameraController.enableTextRecognition = recognitionMode == .qrAndText

        if viewModel.authorizationState == .notDetermined {
            Task {
                await viewModel.requestAccess()
            }
        }
    }

    private var recognitionMode: RecognitionMode {
        RecognitionMode(rawValue: recognitionModeRaw) ?? .qrOnly
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
