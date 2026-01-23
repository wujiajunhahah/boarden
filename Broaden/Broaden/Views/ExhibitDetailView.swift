import SwiftUI
import UIKit
import MapKit
import VisionKit
import Vision

// MARK: - 主体提取视图组件

/// 主体提取图片视图 - 使用 VisionKit 从图片中提取主体（iOS 16+）
/// 实现 "撕下贴纸" 效果，自动从背景中提取主体并生成透明背景图片
/// 参考: WWDC23 Session 10176 "Lift subjects from images in your app"
@available(iOS 16.0, *)
struct ArtifactSubjectView: View {
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
            VStack(alignment: .leading, spacing: 20) {
                // 主体提取照片区域 - 使用 VisionKit 自动去除背景
                if let url = appState.artifactPhotoURL(for: exhibit.id),
                   let image = UIImage(contentsOfFile: url.path) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("文物主体")
                            .font(.headline)

                        // 使用主体提取视图，放大填充整个区域
                        Group {
                            if #available(iOS 16.0, *) {
                                ArtifactSubjectView(originalImage: image)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: UIScreen.main.bounds.width * 1.2) // 更大的高度
                                    .background(Color.white.opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                // iOS 16 以下降级方案
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .rotationEffect(.degrees(90))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: UIScreen.main.bounds.width * 1.2)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .accessibilityLabel("文物主体照片")
                    }
                }

                // 手语视频 - 直接加载，不做延迟
                // 放大 WebView 使数字人占满显示区域（16:9 宽高比，更紧凑）
                SignVideoPlayer(
                    filename: exhibit.media.signVideoFilename,
                    textForTranslation: viewModel.generatedEasyText ?? exhibit.easyText,
                    coordinator: avatarCoordinator
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: UIScreen.main.bounds.width * 1.1) // 固定高度，略大于宽度
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("手语解说视频")
                    .accessibilityHint("展品的手语解说")
                    .onChange(of: avatarCoordinator.isLoaded) { _, isLoaded in
                        // 数字人加载完成后，自动发送讲解脚本
                        if isLoaded {
                            let text = viewModel.generatedEasyText ?? exhibit.easyText
                            if !text.isEmpty {
                                avatarCoordinator.sendText(text)
                            }
                        }
                    }
                    .onChange(of: viewModel.generatedEasyText) { _, newValue in
                        // 当生成的易读版文本更新时，自动发送到数字人进行翻译
                        if let text = newValue, !text.isEmpty, avatarCoordinator.isLoaded {
                            avatarCoordinator.sendText(text)
                        }
                    }

                CaptionView(
                    captions: CaptionService().loadCaptions(filename: exhibit.media.captionsVttOrSrtFilename),
                    size: captionSize,
                    backgroundEnabled: captionBackgroundEnabled,
                    reduceTransparency: reduceTransparency
                )
                .accessibilityLabel("字幕")
                .accessibilityHint("展品解说字幕")

                VStack(alignment: .leading, spacing: 8) {
                    Text("易读版")
                        .font(.headline)
                    Text(viewModel.generatedEasyText ?? exhibit.easyText)
                        .font(.body)
                }

                DisclosureGroup(isExpanded: $viewModel.showDetailText) {
                    Text(viewModel.generatedDetailText ?? exhibit.detailText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                } label: {
                    Text("详细信息")
                        .font(.headline)
                }
                .accessibilityLabel("详细信息")
                .accessibilityHint("展开查看完整解说")

                GlossaryChips(items: exhibit.glossary)

                if let location = appState.locationRecord(for: exhibit.id) {
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
                        VStack(alignment: .leading, spacing: 8) {
                            Text("拍摄位置")
                                .font(.headline)
                            Text(location.displayName)
                                .font(.body)
                            Text(String(format: "%.5f, %.5f", location.latitude, location.longitude))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("拍摄位置")
                    .accessibilityHint("打开地图查看位置并导航")
                }

                HStack(spacing: 12) {
                    Button {
                        viewModel.toggleFavorite(exhibitId: exhibit.id)
                    } label: {
                        Label(viewModel.isFavorite ? "已收藏" : "收藏", systemImage: viewModel.isFavorite ? "heart.fill" : "heart")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(viewModel.isFavorite ? "已收藏" : "收藏")
                    .accessibilityHint("将展品加入收藏")

                    Button {
                        Haptics.lightImpact()
                    } label: {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("分享")
                    .accessibilityHint("分享展品信息")
                }

                AskView(exhibit: exhibit, viewModel: askViewModel, avatarCoordinator: avatarCoordinator)
            }
            .padding(20)
        }
        .navigationTitle(exhibit.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadGeneratedNarration(title: exhibit.title)
        }
    }

    private var captionSize: CaptionSize {
        CaptionSize(rawValue: captionSizeRaw) ?? .medium
    }
}

private struct GlossaryChips: View {
    let items: [GlossaryItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("术语卡片")
                .font(.headline)
            FlexibleTagLayout(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.term)
                        .font(.subheadline.weight(.semibold))
                    Text(item.def)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(item.term)
                .accessibilityHint(item.def)
            }
        }
    }
}
