import SwiftUI
import UIKit
import MapKit
import VisionKit
import Vision

// MARK: - 主体提取视图组件

/// 主体提取图片视图 - 使用 VisionKit 从图片中提取主体（iOS 16+）
/// 实现 "撕下贴纸" 效果，自动从背景中提取主体并生成透明背景图片
/// 参考: WWDC23 Session 10176 "Lift subjects from images in your app"
/// Swift 6 兼容：使用 @MainActor 隔离和 Sendable 类型
@available(iOS 16.0, *)
struct ArtifactSubjectView: View, Sendable {
    let originalImage: UIImage

    @State private var liftedImage: UIImage?
    @State private var isProcessing = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let lifted = liftedImage {
                    // 显示提取后的透明背景图片（"撕下"效果）
                    // 顺时针旋转90度并放大填充
                    Image(uiImage: lifted)
                        .resizable()
                        .scaledToFill()
                        .rotationEffect(.degrees(90))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                } else if isProcessing {
                    // 加载中
                    ProgressView()
                        .scaleEffect(1.2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // 显示原始图片（降级方案）
                    // 顺时针旋转90度并放大填充
                    Image(uiImage: originalImage)
                        .resizable()
                        .scaledToFill()
                        .rotationEffect(.degrees(90))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            }
            .task {
                await extractSubject()
            }
        }
    }

    /// 自动提取主体 - 使用 Vision 框架的 VNGenerateForegroundInstanceMaskRequest
    @MainActor
    private func extractSubject() async {
        isProcessing = true
        defer { isProcessing = false }

        // iOS 17+ 使用 VNGenerateForegroundInstanceMaskRequest 自动提取
        if #available(iOS 17.0, *) {
            await extractWithVision()
        } else {
            // iOS 16 使用 ImageAnalysisInteraction 方式
            await extractWithImageAnalysis()
        }
    }

    /// iOS 17+ 自动提取（使用 Vision 的 VNGenerateForegroundInstanceMaskRequest）
    /// 参考: WWDC23 Session 10176 "Lift subjects from images in your app"
    @available(iOS 17.0, *)
    private func extractWithVision() async {
        guard let cgImage = originalImage.cgImage else { return }

        // 使用 VNGenerateForegroundInstanceMaskRequest 自动生成前景掩码
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])

            guard let result = request.results?.first else {
                return
            }

            // 使用 generateMaskedImage 方法生成高分辨率透明背景图像
            // allInstances 包含所有实例的索引，我们选择所有实例
            let instances = result.allInstances

            do {
                let maskedPixelBuffer = try result.generateMaskedImage(
                    ofInstances: instances,
                    from: handler,
                    croppedToInstancesExtent: false
                )
                // 将 CVPixelBuffer 转换为 UIImage
                liftedImage = uiImageFromPixelBuffer(maskedPixelBuffer)
            } catch {
                print("[ArtifactSubjectView] generateMaskedImage error: \(error)")
            }
        } catch {
            print("[ArtifactSubjectView] Vision extraction failed: \(error)")
        }
    }

    /// 将 CVPixelBuffer 转换为 UIImage
    private func uiImageFromPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    /// iOS 16 使用 ImageAnalysisInteraction 方式
    private func extractWithImageAnalysis() async {
        do {
            let analyzer = ImageAnalyzer()
            let configuration = ImageAnalyzer.Configuration([])
            let analysis = try await analyzer.analyze(originalImage, configuration: configuration)

            let interaction = ImageAnalysisInteraction()
            interaction.analysis = analysis
            interaction.preferredInteractionTypes = .imageSubject

            // 注意：iOS 16 需要用户交互才能获取主体，这里设置好交互环境
        } catch {
            print("[ArtifactSubjectView] ImageAnalysis failed: \(error)")
        }
    }
}

// MARK: - ExhibitDetailView

/// 展品详情视图 - Swift 6 兼容，支持 iOS 26 Liquid Glass
struct ExhibitDetailView: View {
    let exhibit: Exhibit

    @StateObject private var viewModel: ExhibitDetailViewModel
    @StateObject private var askViewModel = AskViewModel()
    /// 手语数字人协调器 - 用于控制数字人播放，实现跨组件联动
    @StateObject private var avatarCoordinator = AvatarCoordinator()
    @EnvironmentObject private var appState: AppState

    @AppStorage("captionSize") private var captionSizeRaw = CaptionSize.medium.rawValue
    @AppStorage("captionBackground") private var captionBackgroundEnabled = true

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(exhibit: Exhibit) {
        self.exhibit = exhibit
        _viewModel = StateObject(wrappedValue: ExhibitDetailViewModel(exhibitId: exhibit.id))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - 主体提取照片区域
                artifactPhotoSection
                
                // MARK: - 文物信息区域
                exhibitInfoSection
                
                // MARK: - 拍摄位置
                locationSection
                
                // MARK: - 数字人区域（Liquid Glass 卡片）
                signLanguageSection
                
                // MARK: - 问答区域
                AskView(exhibit: exhibit, viewModel: askViewModel, avatarCoordinator: avatarCoordinator)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color(red: 0.95, green: 0.95, blue: 0.95))
        .navigationTitle(exhibit.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadGeneratedNarration(title: exhibit.title)
        }
    }
    
    // MARK: - View Sections

    @ViewBuilder
    private var artifactPhotoSection: some View {
        if let url = appState.artifactPhotoURL(for: exhibit.id),
           let image = UIImage(contentsOfFile: url.path) {
            // 图片已经在 SubjectMaskingService 中处理过去背景
            // 直接显示，不需要再提取主体
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                .accessibilityLabel("文物主体照片")
        }
    }
    
    @ViewBuilder
    private var signLanguageSection: some View {
        SignVideoPlayer(
            filename: exhibit.media.signVideoFilename,
            textForTranslation: viewModel.generatedEasyText ?? exhibit.easyText,
            coordinator: avatarCoordinator
        )
        .frame(maxWidth: .infinity)
        .aspectRatio(3/4, contentMode: .fit) // 保持 3:4 宽高比，避免压扁
        .modifier(LiquidGlassCardModifier())
        .accessibilityLabel("手语解说视频")
        .accessibilityHint("展品的手语解说")
        .onChange(of: avatarCoordinator.isLoaded) { _, isLoaded in
            if isLoaded {
                let text = viewModel.generatedEasyText ?? exhibit.easyText
                if !text.isEmpty {
                    avatarCoordinator.sendText(text)
                }
            }
        }
        .onChange(of: viewModel.generatedEasyText) { _, newValue in
            if let text = newValue, !text.isEmpty, avatarCoordinator.isLoaded {
                avatarCoordinator.sendText(text)
            }
        }
    }
    
    @ViewBuilder
    private var exhibitInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题行：标题 + 外链 + 收藏
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(exhibit.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    
                    Text("\(exhibit.id)\n\n\(formattedDate)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 16) {
                    Button {
                        Haptics.lightImpact()
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 20))
                            .foregroundStyle(.primary)
                    }
                    .modifier(LiquidGlassButtonModifier())
                    .accessibilityLabel("外部链接")
                    
                    Button {
                        viewModel.toggleFavorite(exhibitId: exhibit.id)
                    } label: {
                        Image(systemName: viewModel.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 20))
                            .foregroundStyle(viewModel.isFavorite ? .yellow : .primary)
                    }
                    .modifier(LiquidGlassButtonModifier())
                    .accessibilityLabel(viewModel.isFavorite ? "已收藏" : "收藏")
                }
            }
            
            // 标签行
            HStack(spacing: 4) {
                ForEach(exhibitTags, id: \.self) { tag in
                    TagChip(text: tag)
                }
            }
            .padding(.top, 6)
            
            // 描述文字
            if !detailTextContent.isEmpty {
                Text(detailTextContent)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("暂无详细介绍")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            
            // 详细按钮（展开易读版和术语卡片）
            Button {
                viewModel.showDetailText.toggle()
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: viewModel.showDetailText ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                    Text("详细")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .modifier(LiquidGlassChipModifier())
            }
            .padding(.top, 6)
            
            // 展开的详细信息（易读版、术语卡片）
            if viewModel.showDetailText {
                expandedDetailSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
    
    @ViewBuilder
    private var expandedDetailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            
            // 易读版（可点击让数字人手语解读）
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("易读版")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button {
                        if !easyTextContent.isEmpty && avatarCoordinator.isLoaded {
                            avatarCoordinator.sendText(easyTextContent)
                            Haptics.lightImpact()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "hand.wave")
                                .font(.system(size: 10))
                            Text("手语解读")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.blue)
                    }
                    .disabled(easyTextContent.isEmpty || !avatarCoordinator.isLoaded)
                    .accessibilityLabel("手语解读易读版")
                }
                if !easyTextContent.isEmpty {
                    Text(easyTextContent)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture {
                            if avatarCoordinator.isLoaded {
                                avatarCoordinator.sendText(easyTextContent)
                                Haptics.lightImpact()
                            }
                        }
                } else {
                    Text("暂无易读版内容")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            
            // 术语卡片（可点击获取大模型详细解释）
            if !exhibit.glossary.isEmpty {
                GlossaryChips(
                    items: exhibit.glossary,
                    exhibit: exhibit,
                    askViewModel: askViewModel,
                    avatarCoordinator: avatarCoordinator
                )
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private var locationSection: some View {
        if let location = appState.locationRecord(for: exhibit.id) {
            VStack(alignment: .leading, spacing: 8) {
                Text("拍摄位置")
                    .font(.system(size: 12, weight: .semibold))
                
                Button {
                    let coordinate = CLLocationCoordinate2D(
                        latitude: location.latitude,
                        longitude: location.longitude
                    )
                    let placemark = MKPlacemark(coordinate: coordinate)
                    let mapItem = MKMapItem(placemark: placemark)
                    mapItem.name = location.displayName
                    mapItem.openInMaps()
                } label: {
                    HStack {
                        Image(systemName: "location.fill")
                            .font(.system(size: 14))
                        Text(location.displayName)
                            .font(.system(size: 13))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.blue)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .modifier(LiquidGlassCardModifier())
                }
                .accessibilityLabel("在地图中打开 \(location.displayName)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Computed Properties
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.M.dd"
        return formatter.string(from: Date())
    }
    
    private var exhibitTags: [String] {
        // 从术语表中提取标签，或使用默认标签
        var tags: [String] = []
        if !exhibit.glossary.isEmpty {
            tags = exhibit.glossary.prefix(3).map { $0.term }
        }
        if tags.isEmpty {
            tags = ["文物", "博物馆"]
        }
        return tags
    }

    private var captionSize: CaptionSize {
        CaptionSize(rawValue: captionSizeRaw) ?? .medium
    }
    
    /// 清理后的详细版文本
    private var detailTextContent: String {
        let text = viewModel.generatedDetailText ?? exhibit.detailText
        return cleanTextContent(text)
    }
    
    /// 清理后的易读版文本
    private var easyTextContent: String {
        let text = viewModel.generatedEasyText ?? exhibit.easyText
        return cleanTextContent(text)
    }
    
    /// 清理文本内容，移除只有标点符号或空白的无效内容
    private func cleanTextContent(_ text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 如果只有标点符号（如 ":" 或 "："），视为空
        let punctuationOnly = cleaned.allSatisfy { $0.isPunctuation || $0.isWhitespace }
        return punctuationOnly ? "" : cleaned
    }
}

// MARK: - iOS 26 Liquid Glass Modifiers

/// Liquid Glass 卡片修饰符 - iOS 26+ 使用玻璃效果，低版本使用白色背景
private struct LiquidGlassCardModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(in: .rect(cornerRadius: 20))
        } else {
            content
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

/// Liquid Glass 按钮修饰符 - iOS 26+ 使用玻璃效果
private struct LiquidGlassButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glass)
        } else {
            content
                .buttonStyle(.plain)
        }
    }
}

/// Liquid Glass 标签修饰符 - iOS 26+ 使用玻璃效果，低版本使用灰色背景
private struct LiquidGlassChipModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(in: .capsule)
        } else {
            content
                .background(Color(red: 0.80, green: 0.80, blue: 0.80))
                .clipShape(Capsule())
        }
    }
}

/// 标签芯片组件 - 支持 Liquid Glass
private struct TagChip: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .modifier(TagChipBackgroundModifier())
    }
}

private struct TagChipBackgroundModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(in: .capsule)
        } else {
            content
                .background(.white)
                .clipShape(Capsule())
        }
    }
}

// MARK: - GlossaryChips

private struct GlossaryChips: View {
    let items: [GlossaryItem]
    let exhibit: Exhibit
    @ObservedObject var askViewModel: AskViewModel
    @ObservedObject var avatarCoordinator: AvatarCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("术语卡片")
                    .font(.system(size: 12, weight: .semibold))
                Text("(点击获取详细解释)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            FlexibleTagLayout(items) { item in
                GlossaryChipItem(
                    item: item,
                    exhibit: exhibit,
                    askViewModel: askViewModel,
                    avatarCoordinator: avatarCoordinator
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GlossaryChipItem: View {
    let item: GlossaryItem
    let exhibit: Exhibit
    @ObservedObject var askViewModel: AskViewModel
    @ObservedObject var avatarCoordinator: AvatarCoordinator
    
    var body: some View {
        Button {
            // 点击术语卡片，通过大模型获取详细解释
            let question = "请详细解释「\(item.term)」这个术语在\(exhibit.title)中的含义和重要性"
            let contextText = """
            标题：\(exhibit.title)
            简介：\(exhibit.shortIntro)
            术语：\(item.term)
            基础解释：\(item.def)
            """
            askViewModel.ask(exhibitId: exhibit.id, question: question, contextText: contextText)
            Haptics.lightImpact()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.term)
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "sparkles")
                        .font(.system(size: 8))
                        .foregroundStyle(.blue)
                }
                Text(item.def)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(8)
            .frame(maxWidth: 150, alignment: .leading)
            .modifier(GlossaryChipBackgroundModifier())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.term)
        .accessibilityHint("点击获取详细解释：\(item.def)")
    }
}

private struct GlossaryChipBackgroundModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(in: .rect(cornerRadius: 12))
        } else {
            content
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
