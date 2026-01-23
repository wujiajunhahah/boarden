import SwiftUI

// MARK: - Design Tokens
extension Color {
    static var primaryBackground: Color { Color(red: 0xF2/255, green: 0xF0/255, blue: 0xEA/255) }
    static var cardBeige: Color { Color(red: 0xDA/255, green: 0xD5/255, blue: 0xC1/255) }
    static var accentBrown: Color { Color(red: 0x9F/255, green: 0xB0/255, blue: 0x69/255) }
    static var accentGreen: Color { Color(red: 0x9F/255, green: 0xB1/255, blue: 0x68/255) }
    static var primaryText: Color { Color(red: 0x20/255, green: 0x20/255, blue: 0x20/255) }
    static var secondaryText: Color { Color(red: 0x56/255, green: 0x56/255, blue: 0x56/255) }
}

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedMuseum: String? = nil

    private let museums = ["国博", "北大博物馆", "故宫博物院", "圆明园"]

    var body: some View {
        ZStack {
            // 背景图片
            if let bgUrl = Bundle.main.url(forResource: "home-background", withExtension: "png"),
               let bgData = try? Data(contentsOf: bgUrl),
               let bgImage = UIImage(data: bgData) {
                Image(uiImage: bgImage)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            }

            ScrollView {
                VStack(spacing: 0) {
                    // Header Section
                    headerSection

                    // Quick Actions - 原有功能
                    quickActionsSection
                        .padding(.top, 20)

                    // Featured Exhibitions - 新设计
                    featuredSection
                        .padding(.top, 20)

                    // Museum Filter - 新设计
                    museumFilterSection
                        .padding(.top, 20)

                    // Exhibition List - 整合原有最近浏览
                    exhibitionListSection
                        .padding(.top, 16)
                        .padding(.bottom, 100)
                }
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Location
            HStack(spacing: 4) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.8))
                Text("Beijing")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.8))
            }

            // Greeting
            Text("Hi，")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)

            Text("平花选手")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 24)
        .padding(.top, 60)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Quick Actions (原有功能)
    private var quickActionsSection: some View {
        VStack(spacing: 12) {
            // 开始导览按钮
            NavigationLink {
                CameraGuideView()
            } label: {
                HStack {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 18))
                    Text("进入相机导览")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.accentBrown)
                .cornerRadius(16)
            }
            .accessibilityLabel("进入相机导览")
            .accessibilityHint("打开相机识别展品")

            // 无障碍提示卡片
            HStack(spacing: 12) {
                Image(systemName: "captions.bubble")
                    .font(.title2)
                    .foregroundStyle(Color.accentBrown)

                VStack(alignment: .leading, spacing: 4) {
                    Text("无障碍提示")
                        .font(.headline)
                        .foregroundStyle(Color.primaryText)
                    Text("字幕字号与背景遮罩可在设置中调整。")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondaryText)
                }
                Spacer()
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel("无障碍提示")
            .accessibilityHint("字幕字号与背景遮罩可在设置中调整")
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Featured Section
    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("展览资讯")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.primaryText)
                .padding(.horizontal, 24)

            HStack(spacing: 12) {
                ForEach(0..<2) { index in
                    FeaturedCard(
                        title: index == 0 ? "九重之下" : "紫砂成器",
                        subtitle: "国家博物馆",
                        date: index == 0 ? "11.04-12.08 周末" : "10.15-01.30 周末"
                    )
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Museum Filter
    private var museumFilterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(museums, id: \.self) { museum in
                    MuseumChip(
                        title: museum,
                        isSelected: selectedMuseum == museum
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) {
                            selectedMuseum = selectedMuseum == museum ? nil : museum
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Exhibition List (整合原有最近浏览)
    private var exhibitionListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("历史行程")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
                Spacer()
            }
            .padding(.horizontal, 24)

            if recentExhibits.isEmpty {
                Text("暂无记录")
                    .font(.body)
                    .foregroundStyle(Color.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                VStack(spacing: 12) {
                    ForEach(recentExhibits.prefix(3), id: \.id) { exhibit in
                        NavigationLink {
                            ExhibitDetailView(exhibit: exhibit)
                        } label: {
                            HistoryRowView(exhibit: exhibit)
                        }
                        .accessibilityLabel(exhibit.title)
                        .accessibilityHint("查看展品详情")
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Recent Exhibits (原有功能)
    private var recentExhibits: [Exhibit] {
        appState.recentExhibitIds.compactMap { appState.exhibit(by: $0) }
    }
}

// MARK: - Star Shape
private var starShape: some Shape {
    Circle()
}

// MARK: - Featured Card
struct FeaturedCard: View {
    let title: String
    let subtitle: String
    let date: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image placeholder
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0x8B/255, green: 0x45/255, blue: 0x13/255),
                            Color(red: 0x6B/255, green: 0x3A/255, blue: 0x0F/255)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(
                    Image(systemName: "photo.artframe")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.6))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)

                Text("展览 | \(date)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
        .background(.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Museum Chip
struct MuseumChip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isSelected ? .white : Color.secondaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentBrown : Color.white)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(isSelected ? 0.15 : 0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Exhibition Card
struct ExhibitionCard: View {
    let title: String
    let museum: String
    let date: String

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Rectangle()
                .fill(Color.cardBeige.opacity(0.6))
                .frame(width: 62, height: 62)
                .cornerRadius(12)
                .overlay(
                    Image(systemName: "museum.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.secondaryText.opacity(0.5))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.primaryText)

                HStack(spacing: 4) {
                    Image(systemName: "location")
                        .font(.system(size: 10))
                    Text(museum)
                        .font(.system(size: 11))
                }
                .foregroundStyle(Color.secondaryText)

                Text(date)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondaryText.opacity(0.7))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Color.secondaryText.opacity(0.5))
        }
        .padding(14)
        .background(Color.cardBeige.opacity(0.4))
        .cornerRadius(16)
    }
}

// MARK: - History Row View
private struct HistoryRowView: View {
    let exhibit: Exhibit

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail with gradient
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0xD2/255, green: 0x69/255, blue: 0x1E/255),
                            Color(red: 0xB8/255, green: 0x55/255, blue: 0x18/255)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.7))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(exhibit.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)

                Text(exhibit.shortIntro)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(1)

                Text(formattedDate)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondaryText.opacity(0.8))
            }

            Spacer()
        }
        .padding(12)
        .background(.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: Date())
    }
}

// MARK: - Preview
#Preview {
    HomeView()
        .environmentObject(AppState())
}
