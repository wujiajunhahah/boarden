import AVKit
import SwiftUI

struct SignVideoPlayer: View {
    let filename: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let url = Bundle.main.url(forResource: filename, withExtension: nil) {
            VideoPlayer(player: AVPlayer(url: url))
                .onAppear {
                    Haptics.lightImpact()
                }
        } else {
            ZStack {
                Rectangle()
                    .fill(.thinMaterial)
                VStack(spacing: 12) {
                    SignGestureAnimation(reduceMotion: reduceMotion)
                        .frame(height: 80)
                        .accessibilityLabel("手语动画占位")
                    Text("手语解说占位")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct SignGestureAnimation: View {
    let reduceMotion: Bool
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 24) {
            Image(systemName: "hand.wave")
                .font(.system(size: 40, weight: .regular))
                .rotationEffect(.degrees(isAnimating ? -12 : 12))
                .offset(y: isAnimating ? -6 : 6)
            Image(systemName: "hand.raised")
                .font(.system(size: 40, weight: .regular))
                .rotationEffect(.degrees(isAnimating ? 10 : -10))
                .offset(y: isAnimating ? 6 : -6)
        }
        .foregroundStyle(.secondary)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isAnimating = true
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
