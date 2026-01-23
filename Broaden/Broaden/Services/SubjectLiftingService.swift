import UIKit
import VisionKit

/// 主体提取服务 - 从图片中提取主体并移除背景（"撕下贴纸"效果）
@available(iOS 16.0, *)
@MainActor
class SubjectLiftingService: ObservableObject {

    @Published private(set) var liftedImage: UIImage?
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var error: Error?

    /// 从指定图片中提取主体
    /// - Parameter image: 原始图片
    /// - Returns: 提取主体后的透明背景图片
    func extractSubject(from image: UIImage) async throws -> UIImage {
        isProcessing = true
        liftedImage = nil
        error = nil

        defer { isProcessing = false }

        guard let analyzer = ImageAnalyzer() else {
            throw SubjectLiftingError.analyzerUnavailable
        }

        // 分析图片
        let analysis = try await analyzer.analyze(image)

        guard let analysis else {
            throw SubjectLiftingError.noSubjectFound
        }

        // 获取所有主体
        let subjects = analysis.allSubjects

        guard !subjects.isEmpty else {
            throw SubjectLiftingError.noSubjectFound
        }

        // 使用第一个主要主体
        let primarySubject = subjects.first

        // 创建 ImageAnalysisInteraction
        let interaction = ImageAnalysisInteraction()
        interaction.analysis = analysis
        interaction.preferredInteractionTypes = .imageSubject

        // 生成提取后的图片
        let liftedImage = try await interaction.image(for: [primarySubject])

        self.liftedImage = liftedImage
        return liftedImage
    }

    /// 从指定路径加载图片并提取主体
    /// - Parameter imagePath: 图片路径
    /// - Returns: 提取主体后的透明背景图片
    func extractSubject(from imagePath: String) async throws -> UIImage {
        guard let image = UIImage(contentsOfFile: imagePath) else {
            throw SubjectLiftingError.imageLoadFailed(path: imagePath)
        }
        return try await extractSubject(from: image)
    }
}

// MARK: - Errors

enum SubjectLiftingError: LocalizedError {
    case analyzerUnavailable
    case noSubjectFound
    case imageLoadFailed(path: String)

    var errorDescription: String? {
        switch self {
        case .analyzerUnavailable:
            return "图片分析器不可用"
        case .noSubjectFound:
            return "未检测到可提取的主体"
        case .imageLoadFailed(let path):
            return "无法加载图片: \(path)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .analyzerUnavailable:
            return "请确保设备支持 VisionKit（iOS 16+）"
        case .noSubjectFound:
            return "请尝试使用更清晰的图片"
        case .imageLoadFailed:
            return "请检查图片路径是否正确"
        }
    }
}

// MARK: - SwiftUI View

/// 主体提取图片视图 - 显示带有"撕下贴纸"效果的图片
/// 优化布局：使用 frame 和 clipped 确保内容不会溢出父容器
@available(iOS 16.0, *)
struct SubjectLiftedImageView: View {
    let originalImage: UIImage
    @StateObject private var service = SubjectLiftingService()

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let liftedImage = service.liftedImage {
                    // 显示提取后的图片（透明背景）
                    Image(uiImage: liftedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                } else if service.isProcessing {
                    // 加载中状态 - 居中显示
                    ProgressView()
                        .scaleEffect(1.2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // 显示原始图片 - 降级方案
                    Image(uiImage: originalImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            }
        }
        .task {
            do {
                _ = try await service.extractSubject(from: originalImage)
            } catch {
                print("[SubjectLiftedImageView] 提取失败: \(error.localizedDescription)")
                // 静默失败，继续显示原始图片
            }
        }
    }
}

// MARK: - UIView Wrapper

/// 用于 UIKit 集成的主体提取图片视图
@available(iOS 16.0, *)
class SubjectLiftedImageUIView: UIView {

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        return view
    }()

    private let interaction = ImageAnalysisInteraction()
    private var analysis: ImageAnalysis?

    /// 设置图片并提取主体
    /// - Parameter image: 原始图片
    func setImageAndExtractSubject(_ image: UIImage) {
        imageView.image = image
        imageView.removeInteraction(interaction)

        Task { @MainActor in
            do {
                // 分析图片
                guard let analyzer = ImageAnalyzer() else { return }
                self.analysis = try await analyzer.analyze(image)

                guard let analysis = self.analysis else { return }

                // 配置交互
                self.interaction.analysis = analysis
                self.interaction.preferredInteractionTypes = .imageSubject
                imageView.addInteraction(self.interaction)

                // 获取主体
                let subjects = analysis.allSubjects
                guard !subjects.isEmpty else { return }

                // 生成提取后的图片
                let liftedImage = try await self.interaction.image(for: [subjects.first!])

                // 更新显示
                UIView.transition(with: imageView, duration: 0.3, options: .transitionCrossDissolve) {
                    self.imageView.image = liftedImage
                }
            } catch {
                print("[SubjectLiftedImageView] 错误: \(error)")
            }
        }
    }
}

// MARK: - Preview

@available(iOS 16.0, *)
#Preview {
    SubjectLiftedImageView(originalImage: UIImage(named: "AppIcon-1024") ?? UIImage())
        .frame(width: 300, height: 300)
        .padding()
        .background(Color.gray.opacity(0.1))
}

// UIKit Preview
@available(iOS 16.0, *)
#Preview("UIKit Version") {
    SubjectLiftedImageUIView()
}
