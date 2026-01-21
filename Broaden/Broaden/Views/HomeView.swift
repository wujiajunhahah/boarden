import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("开始导览")
                        .font(.title.bold())
                    Text("对准展品或展牌，自动显示手语解说与字幕。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                NavigationLink {
                    CameraGuideView()
                } label: {
                    Label("进入相机导览", systemImage: "camera.viewfinder")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("进入相机导览")
                .accessibilityHint("打开相机识别展品")

                AccessibilityHintCard()

                VStack(alignment: .leading, spacing: 12) {
                    Text("最近浏览")
                        .font(.title3.weight(.semibold))
                    if recentExhibits.isEmpty {
                        Text("暂无记录")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recentExhibits, id: \.id) { exhibit in
                            NavigationLink {
                                ExhibitDetailView(exhibit: exhibit)
                            } label: {
                                ExhibitRowView(exhibit: exhibit)
                            }
                            .accessibilityLabel(exhibit.title)
                            .accessibilityHint("查看展品详情")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
        }
        .navigationTitle("博听 Broaden")
    }

    private var recentExhibits: [Exhibit] {
        appState.recentExhibitIds.compactMap { appState.exhibit(by: $0) }
    }
}

private struct ExhibitRowView: View {
    let exhibit: Exhibit

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(exhibit.title)
                    .font(.headline)
                Text(exhibit.shortIntro)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct AccessibilityHintCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "caption.bubble")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("无障碍提示")
                    .font(.headline)
                Text("字幕字号与背景遮罩可在设置中调整。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel("无障碍提示")
        .accessibilityHint("字幕字号与背景遮罩可在设置中调整")
    }
}
