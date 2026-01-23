import AVKit
import SwiftUI

struct SignVideoPlayer: View {
    let filename: String
    /// 用于手语数字人翻译的文本（当没有本地视频时使用）
    var textForTranslation: String = ""
    /// 可选：外部传入的协调器（用于跨视图共享控制和实现自动联动）
    var coordinator: AvatarCoordinator?
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var internalCoordinator = AvatarCoordinator()
    
    /// 实际使用的协调器
    private var activeCoordinator: AvatarCoordinator {
        coordinator ?? internalCoordinator
    }

    var body: some View {
        if let url = Bundle.main.url(forResource: filename, withExtension: nil) {
            // 优先使用本地视频文件
            VideoPlayer(player: AVPlayer(url: url))
                .onAppear {
                    Haptics.lightImpact()
                }
        } else {
            // 使用手语数字人服务进行实时翻译
            SignLanguageAvatarView(
                textToTranslate: textForTranslation,
                externalCoordinator: activeCoordinator
            )
            .onAppear {
                Haptics.lightImpact()
            }
            .onChange(of: textForTranslation) { _, newValue in
                // 当翻译文本变化时，自动发送到数字人（实现脚本更新即时翻译）
                if activeCoordinator.isLoaded && !newValue.isEmpty {
                    activeCoordinator.sendText(newValue)
                }
            }
        }
    }
}

struct CaptionView: View {
    let captions: [CaptionEntry]
    let size: CaptionSize
    let backgroundEnabled: Bool
    let reduceTransparency: Bool

    var body: some View {
        let text = captions.map { $0.text }.joined(separator: " ")
        let display = text.isEmpty ? "字幕示例：此处显示解说字幕。" : text

        Text(display)
            .font(font)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundView)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var font: Font {
        switch size {
        case .small: return .callout
        case .medium: return .body
        case .large: return .title3
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        if backgroundEnabled {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.65))
            } else {
                RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial)
            }
        } else {
            RoundedRectangle(cornerRadius: 12).fill(Color.clear)
        }
    }
}

struct FlexibleTagLayout<Item: Hashable, ItemView: View>: View {
    let items: [Item]
    let spacing: CGFloat
    let rowSpacing: CGFloat
    let content: (Item) -> ItemView

    init(_ items: [Item], spacing: CGFloat = 8, rowSpacing: CGFloat = 8, @ViewBuilder content: @escaping (Item) -> ItemView) {
        self.items = items
        self.spacing = spacing
        self.rowSpacing = rowSpacing
        self.content = content
    }

    var body: some View {
        LayoutFlow(spacing: spacing, rowSpacing: rowSpacing) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}

struct LayoutFlow: Layout {
    let spacing: CGFloat
    let rowSpacing: CGFloat

    init(spacing: CGFloat = 8, rowSpacing: CGFloat = 8) {
        self.spacing = spacing
        self.rowSpacing = rowSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var currentRowWidth: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width > maxWidth {
                totalHeight += currentRowHeight + rowSpacing
                totalWidth = max(totalWidth, currentRowWidth)
                currentRowWidth = size.width + spacing
                currentRowHeight = size.height
            } else {
                currentRowWidth += size.width + spacing
                currentRowHeight = max(currentRowHeight, size.height)
            }
        }

        totalHeight += currentRowHeight
        totalWidth = max(totalWidth, currentRowWidth)
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = CGPoint(x: bounds.minX, y: bounds.minY)
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > bounds.maxX {
                origin.x = bounds.minX
                origin.y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(at: origin, proposal: ProposedViewSize(width: size.width, height: size.height))
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
