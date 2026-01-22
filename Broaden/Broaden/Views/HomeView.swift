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
    @Binding var selectedTab: AppTab
    @State private var selectedMuseum: String? = nil

    private let museums = ["国博", "北大博物馆", "故宫博物院", "圆明园"]

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    // Header Section
                    headerSection

                    // Featured Exhibitions
                    featuredSection
                        .padding(.top, 24)

                    // Museum Filter
                    museumFilterSection
                        .padding(.top, 20)

                    // Exhibition List
                    exhibitionListSection
                        .padding(.top, 16)
                        .padding(.bottom, 100)
                }
            }
            .background(Color.primaryBackground)

            // Bottom Navigation
            bottomNavigationBar
        }
        .navigationBarHidden(true)
    }

    // MARK: - Header Section
    private var headerSection: some View {
        ZStack(alignment: .topLeading) {
            // Background decoration
            VStack {
                Spacer()
                HStack {
                    starShape
                        .fill(Color.accentGreen.opacity(0.3))
                        .frame(width: 120, height: 120)
                        .offset(x: -20, y: 40)
                    Spacer()
                    starShape
                        .fill(Color(red: 0xFF/255, green: 0xE8/255, blue: 0x92/255).opacity(0.4))
                        .frame(width: 80, height: 80)
                        .offset(x: 20, y: -30)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                // Location
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondaryText)
                    Text("Beijing")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.secondaryText)
                }
                .padding(.top, 60)

                // Greeting
                Text("Hi，")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.primaryText)

                Text("平花选手")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.primaryText)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Featured Section
    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("展览资讯")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.primaryText)
                .padding(.horizontal, 24)

            HStack(spacing: 12) {
                ForEach(0..<2) { index in
                    FeaturedCard(
                        title: index == 0 ? "九重之下" : "紫砂成器",
                        subtitle: "国家博物馆",
                        date: index == 0 ? "2023.11.04-2024.02.18" : "2023.10.15-2024.01.30"
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

    // MARK: - Exhibition List
    private var exhibitionListSection: some View {
        VStack(spacing: 12) {
            ForEach(0..<5) { index in
                ExhibitionCard(
                    title: ["古代青铜器展", "明清瓷器精品", "丝绸之路文物", "中国古代书画", "玉器珍品"][index],
                    museum: museums[index % museums.count],
                    date: "2024.01.10 - 2024.03.20"
                )
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Bottom Navigation
    private var bottomNavigationBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: iconName(for: tab))
                            .font(.system(size: 22))
                            .foregroundStyle(selectedTab == tab ? Color.accentBrown : Color.secondaryText)

                        Text(tabTitle(for: tab))
                            .font(.system(size: 11))
                            .foregroundStyle(selectedTab == tab ? Color.accentBrown : Color.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 28)
        .background(
            RoundedRectangle(cornerRadius: 33.5)
                .fill(.white)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -2)
        )
        .padding(.horizontal, 36)
    }

    private func iconName(for tab: AppTab) -> String {
        switch tab {
        case .home: return "doc.text.fill"
        case .camera: return "camera.fill"
        case .profile: return "person.fill"
        }
    }

    private func tabTitle(for tab: AppTab) -> String {
        switch tab {
        case .home: return "展览"
        case .camera: return "拍照"
        case .profile: return "我的"
        }
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
        VStack(alignment: .leading, spacing: 8) {
            // Image placeholder
            Rectangle()
                .fill(Color.cardBeige.opacity(0.5))
                .frame(height: 100)
                .cornerRadius(12)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.secondaryText.opacity(0.5))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondaryText)

                Text(date)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondaryText.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
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

// MARK: - Preview
#Preview {
    HomeView(selectedTab: .constant(.home))
        .environmentObject(AppState())
}
