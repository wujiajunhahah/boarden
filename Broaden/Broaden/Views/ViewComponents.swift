import AVKit
import SwiftUI
import WebKit

struct SignVideoPlayer: View {
    let filename: String
    /// 用于手语数字人翻译的文本（当没有本地视频时使用）
    var textForTranslation: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let url = Bundle.main.url(forResource: filename, withExtension: nil) {
            // 优先使用本地视频文件
            VideoPlayer(player: AVPlayer(url: url))
                .onAppear {
                    Haptics.lightImpact()
                }
        } else if !textForTranslation.isEmpty {
            // 使用手语数字人服务进行实时翻译（APPSecret 已在 HTML 中硬编码）
            SignLanguageAvatarView(textToTranslate: textForTranslation)
                .onAppear {
                    Haptics.lightImpact()
                }
        } else {
            // 加载手语预览页面
            SignLanguagePreviewWebView()
                .onAppear {
                    Haptics.lightImpact()
                }
        }
    }
}

/// 手语预览页面 WebView
private struct SignLanguagePreviewWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        if let url = URL(string: "https://www.broaden.cc/sign_language_preview.html") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
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
