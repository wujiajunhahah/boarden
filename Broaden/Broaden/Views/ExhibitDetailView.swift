import SwiftUI
import UIKit
import MapKit

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
                if let url = appState.artifactPhotoURL(for: exhibit.id),
                   let image = UIImage(contentsOfFile: url.path) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("文物主体照片")
                            .font(.headline)
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("文物主体照片")
                    }
                }

                SignVideoPlayer(
                    filename: exhibit.media.signVideoFilename,
                    textForTranslation: viewModel.generatedEasyText ?? exhibit.easyText,
                    coordinator: avatarCoordinator
                )
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("手语解说视频")
                    .accessibilityHint("展品的手语解说")
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
