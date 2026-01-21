import SwiftUI

struct ExhibitDetailView: View {
    let exhibit: Exhibit

    @StateObject private var viewModel: ExhibitDetailViewModel
    @StateObject private var askViewModel = AskViewModel()

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
                SignVideoPlayer(filename: exhibit.media.signVideoFilename)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("手语解说视频")
                    .accessibilityHint("展品的手语解说")

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
                    Text(exhibit.easyText)
                        .font(.body)
                }

                DisclosureGroup(isExpanded: $viewModel.showDetailText) {
                    Text(exhibit.detailText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                } label: {
                    Text("详细信息")
                        .font(.headline)
                }
                .accessibilityLabel("详细信息")
                .accessibilityHint("展开查看完整解说")

                GlossaryChips(items: exhibit.glossary)

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

                AskView(exhibit: exhibit, viewModel: askViewModel)
            }
            .padding(20)
        }
        .navigationTitle(exhibit.title)
        .navigationBarTitleDisplayMode(.inline)
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
