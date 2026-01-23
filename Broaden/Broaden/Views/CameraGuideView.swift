import SwiftUI
import AVFoundation
import UIKit
import PhotosUI

struct CameraGuideView: View {
    @Binding var selectedTab: AppTab
    
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = CameraGuideViewModel()
    @State private var cameraController = CameraSessionController()
    @State private var showPermissionAlert = false
    @State private var lastCapturedPreview: UIImage?
    @State private var subjectService = SubjectMaskingService()

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isGalleryPresented = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreview(session: cameraController.session)
                .ignoresSafeArea()
                .accessibilityLabel("相机预览")
                .accessibilityHint("对准展品或展牌")

            // 扫描框
            scanFrame
            
            // 顶部导航栏
            VStack {
                topBar
                Spacer()
            }
            
            // 底部控制区
            VStack {
                Spacer()
                statusOverlay
                    .padding(.bottom, 20)
                cameraControls
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
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
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
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
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            // 返回按钮
            Button {
                withAnimation {
                    selectedTab = .home
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
            .accessibilityLabel("返回")
            
            Spacer()
            
            // 设置按钮
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
    
    // MARK: - Scan Frame
    
    private var scanFrame: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height) * 0.7
            let cornerLength: CGFloat = 40
            let cornerWidth: CGFloat = 4
            
            ZStack {
                // 四个角
                // 左上
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        RoundedCorner(cornerRadius: 20, corners: .topLeft)
                            .stroke(Color.white.opacity(0.8), lineWidth: cornerWidth)
                            .frame(width: cornerLength, height: cornerLength)
                        Spacer()
                    }
                    Spacer()
                }
                
                // 右上
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Spacer()
                        RoundedCorner(cornerRadius: 20, corners: .topRight)
                            .stroke(Color.white.opacity(0.8), lineWidth: cornerWidth)
                            .frame(width: cornerLength, height: cornerLength)
                    }
                    Spacer()
                }
                
                // 左下
                VStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: 0) {
                        RoundedCorner(cornerRadius: 20, corners: .bottomLeft)
                            .stroke(Color.white.opacity(0.8), lineWidth: cornerWidth)
                            .frame(width: cornerLength, height: cornerLength)
                        Spacer()
                    }
                }
                
                // 右下
                VStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: 0) {
                        Spacer()
                        RoundedCorner(cornerRadius: 20, corners: .bottomRight)
                            .stroke(Color.white.opacity(0.8), lineWidth: cornerWidth)
                            .frame(width: cornerLength, height: cornerLength)
                    }
                }
            }
            .frame(width: size, height: size)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2 - 40)
        }
    }

    private var statusOverlay: some View {
        VStack(spacing: 16) {
            if case .failed(let message) = viewModel.recognitionState {
                // 失败状态：只显示错误信息
                VStack(spacing: 10) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .accessibilityLabel(message)
                    
                    Button("重试") {
                        viewModel.reset()
                    }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.2), in: Capsule())
                    .accessibilityLabel("重试识别")
                }
            } else {
                // 正常状态：显示步骤指示器和提示
                stepIndicator
                
                VStack(spacing: 6) {
                    Text(stageTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    
                    Text(stageHint)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("\(stageTitle), \(stageHint)")
            }
        }
    }
    
    private var stepIndicator: some View {
        HStack(spacing: 8) {
            // 步骤1
            stepDot(step: 1, isActive: true, isCompleted: currentStep > 1)
            
            // 连接线
            Rectangle()
                .fill(currentStep > 1 ? Color.white : Color.white.opacity(0.3))
                .frame(width: 30, height: 2)
            
            // 步骤2
            stepDot(step: 2, isActive: currentStep >= 2, isCompleted: currentStep > 2)
        }
    }
    
    private func stepDot(step: Int, isActive: Bool, isCompleted: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isCompleted ? Color.green : (isActive ? Color.white : Color.white.opacity(0.3)))
                .frame(width: 28, height: 28)
            
            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text("\(step)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isActive ? .black : .white.opacity(0.5))
            }
        }
    }
    
    private var currentStep: Int {
        switch viewModel.captureStage {
        case .signboard:
            return 1
        case .artifact:
            return 2
        case .done:
            return 3
        }
    }
    
    private var stageTitle: String {
        switch viewModel.captureStage {
        case .signboard:
            return "第一步"
        case .artifact:
            return "第二步"
        case .done:
            return "拍摄完成"
        }
    }

    private var cameraControls: some View {
        VStack(spacing: 20) {
            HStack(alignment: .center, spacing: 0) {
                // 左侧：相册按钮
                Button {
                    isGalleryPresented = true
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                }
                .accessibilityLabel("相册")

                Spacer()

                // 中间：拍照按钮
                Button {
                    cameraController.capturePhoto()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.5), lineWidth: 4)
                            .frame(width: 80, height: 80)

                        Circle()
                            .fill(Color.white)
                            .frame(width: 68, height: 68)

                        if viewModel.isProcessing {
                            ProgressView()
                                .tint(.black)
                        }
                    }
                }
                .disabled(viewModel.isProcessing)
                .accessibilityLabel("拍照")

                Spacer()

                // 右侧：预览/历史按钮
                if let preview = lastCapturedPreview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("最近拍摄")
                } else {
                    Button {
                        // 打开历史记录
                    } label: {
                        Image(systemName: "tray")
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                    }
                    .accessibilityLabel("历史")
                }
            }
            .padding(.horizontal, 40)
        }
        .padding(.bottom, 50)
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

        Task { @MainActor in
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                viewModel.recognitionState = .failed("无法加载选中的照片")
                return
            }

            guard let image = UIImage(data: data) else {
                viewModel.recognitionState = .failed("不支持的图片格式")
                return
            }

            lastCapturedPreview = image

            if case .done = viewModel.captureStage {
                viewModel.reset()
            }

            handlePhotoData(data)
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
            viewModel.reset()
            viewModel.handleSignboardPhoto(data)
        }
    }

    private var stageHint: String {
        switch viewModel.captureStage {
        case .signboard:
            return "对准展牌文字拍摄，识别展品信息"
        case .artifact:
            return "对准文物主体拍摄，保存展品照片"
        case .done:
            return "点击下方查看展品详情"
        }
    }
}

// MARK: - Rounded Corner Shape

private struct RoundedCorner: Shape {
    var cornerRadius: CGFloat
    var corners: UIRectCorner
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: cornerRadius, height: cornerRadius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Exhibit Sheet View

private struct ExhibitSheetView: View {
    @Environment(\.dismiss) private var dismiss
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
            }

            NavigationLink {
                ExhibitDetailView(exhibit: exhibit)
            } label: {
                Label("查看展品详情", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if case .done = stage {
                Button {
                    dismiss()
                } label: {
                    Text("完成")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding(20)
        .onAppear {
            appState.addRecent(exhibit: exhibit)
        }
    }
}
