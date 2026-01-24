import SwiftUI
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Design Tokens
extension Color {
    static var primaryBackground: Color { Color(red: 0xF9/255, green: 0xF6/255, blue: 0xEE/255) }
    static var cardBeige: Color { Color(red: 0xF5/255, green: 0xF2/255, blue: 0xE8/255) }
    static var accentOlive: Color { Color(red: 0x9F/255, green: 0xB0/255, blue: 0x69/255) }
    static var accentYellow: Color { Color(red: 0xF5/255, green: 0xD5/255, blue: 0x6E/255) }
    static var accentPink: Color { Color(red: 0xF0/255, green: 0xC4/255, blue: 0xD4/255) }
    static var accentBlue: Color { Color(red: 0xB8/255, green: 0xC8/255, blue: 0xE8/255) }
    static var tabBarBrown: Color { Color(red: 0x3D/255, green: 0x32/255, blue: 0x22/255) }
    static var primaryText: Color { Color(red: 0x20/255, green: 0x20/255, blue: 0x20/255) }
    static var secondaryText: Color { Color(red: 0x56/255, green: 0x56/255, blue: 0x56/255) }
}

// MARK: - HomeView

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedMuseum: String? = nil

    private let museums = ["国博", "北大博物馆", "故宫博物院", "颐和园"]

    var body: some View {
        ZStack {
            // 背景
            backgroundView

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header Section
                    headerSection
                        .padding(.top, 60)

                    // 展览资讯
                    exhibitionSection
                        .padding(.top, 40)

                    // 历史行程
                    historySection
                        .padding(.top, 24)
                        .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Background View

    @ViewBuilder
    private var backgroundView: some View {
        Image("background_pattern")
            .resizable()
            .ignoresSafeArea()
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hi，")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Color.primaryText)
            
            Text("平花选手")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Color.primaryText)
            
            HStack(spacing: 4) {
                Image(systemName: "mappin")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.secondaryText)
                Text("Beijing")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }
    
    // MARK: - Exhibition Section
    
    private var exhibitionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("展览资讯")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.primaryText)
                .padding(.horizontal, 24)
            
            // 博物馆筛选标签
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(museums, id: \.self) { museum in
                        MuseumFilterChip(
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
            
            // 展览卡片
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ExhibitionCard(
                        title: "九重之下",
                        museum: "故宫博物院",
                        dateRange: "2025.11.04-2026.02.08",
                        imageName: "exhibition_jiuzhong"
                    )
                    
                    ExhibitionCard(
                        title: "爱砚成痴",
                        museum: "故宫博物院",
                        dateRange: "2025.11.04-2026.02.08",
                        imageName: "exhibition_aiyan"
                    )
                }
                .padding(.horizontal, 24)
            }
        }
    }
    
    // MARK: - History Section
    
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("历史行程")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
            
            VStack(spacing: 12) {
                if recentExhibits.isEmpty {
                    // 空状态提示
                    Text("暂无历史记录")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    ForEach(recentExhibits, id: \.id) { exhibit in
                        NavigationLink {
                            ExhibitDetailView(exhibit: exhibit)
                        } label: {
                            HistoryCardFromExhibit(exhibit: exhibit)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }
    
    // MARK: - Recent Exhibits
    
    private var recentExhibits: [Exhibit] {
        appState.recentExhibitIds.compactMap { appState.exhibit(by: $0) }
    }
}

// MARK: - Museum Filter Chip

private struct MuseumFilterChip: View {
    let title: String
    let isSelected: Bool
    
    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isSelected ? .white : Color.primaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .modifier(ChipBackgroundModifier(isSelected: isSelected))
    }
}

private struct ChipBackgroundModifier: ViewModifier {
    let isSelected: Bool
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if isSelected {
                content
                    .background(Color.accentOlive)
                    .clipShape(Capsule())
            } else {
                content
                    .glassEffect(in: .capsule)
            }
        } else {
            content
                .background(isSelected ? Color.accentOlive : Color.cardBeige)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Exhibition Card

private struct ExhibitionCard: View {
    let title: String
    let museum: String
    let dateRange: String
    let imageName: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 图片区域
            exhibitionImage
            
            // 信息区域
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
                
                Text(museum)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)
                
                Text(dateRange)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondaryText.opacity(0.8))
            }
            .padding(12)
        }
        .frame(width: 240)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .modifier(CardBackgroundModifier())
    }
    
    @ViewBuilder
    private var exhibitionImage: some View {
        // 从 Asset Catalog 加载图片
        Image(imageName)
            .resizable()
            .scaledToFill()
            .frame(width: 240, height: 140)
            .clipped()
    }
}

// MARK: - History Card

private struct HistoryCard: View {
    let title: String
    let location: String
    let date: String
    let imageName: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // 左侧文本信息
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(location)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer(minLength: 4)
                
                Text(date)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondaryText.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .padding(.vertical, 16)
            
            Spacer(minLength: 0)
            
            // 右侧占位图
            placeholderImage
                .padding(.trailing, 20)
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .modifier(HistoryCardBackgroundModifier())
    }
    
    @ViewBuilder
    private var placeholderImage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.85, green: 0.80, blue: 0.75),
                            Color(red: 0.90, green: 0.85, blue: 0.80)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: "photo")
                .font(.system(size: 24))
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .frame(width: 80, height: 80)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - History Card From Exhibit

private struct HistoryCardFromExhibit: View {
    let exhibit: Exhibit
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // 左侧文本信息
            VStack(alignment: .leading, spacing: 6) {
                Text(exhibit.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(exhibit.shortIntro)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer(minLength: 4)
                
                Text(formattedDate)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondaryText.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, 20)
            .padding(.trailing, 8)
            .padding(.vertical, 16)
            
            // 右侧文物抠图 - 占满高度
            artifactImage
                .frame(width: 120, height: 120)
                .clipped()
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .modifier(HistoryCardBackgroundModifier())
    }
    
    @ViewBuilder
    private var artifactImage: some View {
        if let url = appState.artifactPhotoURL(for: exhibit.id),
           let uiImage = UIImage(contentsOfFile: url.path) {
            // 图片已经在 SubjectMaskingService 中处理过去背景
            // 直接显示，不需要再处理或旋转
            HistoryCardArtifactImage(originalImage: uiImage)
        } else {
            // 占位图
            ZStack {
                Color.clear
                Image(systemName: "photo.artframe")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.secondaryText.opacity(0.3))
            }
        }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.M.dd"
        return formatter.string(from: Date())
    }
}

// MARK: - History Card Artifact Image
// 图片已经在 SubjectMaskingService 中处理过去背景，直接显示即可

private struct HistoryCardArtifactImage: View {
    let originalImage: UIImage

    var body: some View {
        Image(uiImage: originalImage)
            .resizable()
            .scaledToFit()
            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
    }
}

// iOS 16 及以下的降级版本（与上面相同）
private struct HistoryCardArtifactImageFallback: View {
    let originalImage: UIImage

    var body: some View {
        Image(uiImage: originalImage)
            .resizable()
            .scaledToFit()
            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
    }
}

// MARK: - History Card Background Modifier (iOS 26 Liquid Glass)

private struct HistoryCardBackgroundModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(in: .rect(cornerRadius: 20))
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.white.opacity(0.7))
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
                )
        }
    }
}

// MARK: - Card Background Modifier (iOS 26 Liquid Glass)

private struct CardBackgroundModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(in: .rect(cornerRadius: 16))
        } else {
            content
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
    }
}

// MARK: - Irregular Shapes for Background

private struct IrregularShape1: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.3, y: 0))
        path.addCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.4),
            control1: CGPoint(x: rect.width * 0.7, y: 0),
            control2: CGPoint(x: rect.width, y: rect.height * 0.1)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.6, y: rect.height),
            control1: CGPoint(x: rect.width, y: rect.height * 0.8),
            control2: CGPoint(x: rect.width * 0.9, y: rect.height)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: rect.height * 0.5),
            control1: CGPoint(x: rect.width * 0.2, y: rect.height),
            control2: CGPoint(x: 0, y: rect.height * 0.8)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.3, y: 0),
            control1: CGPoint(x: 0, y: rect.height * 0.2),
            control2: CGPoint(x: rect.width * 0.1, y: 0)
        )
        path.closeSubpath()
        return path
    }
}

private struct IrregularShape2: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 0, y: 0, width: rect.width * 0.6, height: rect.height * 0.8))
        path.addEllipse(in: CGRect(x: rect.width * 0.4, y: rect.height * 0.2, width: rect.width * 0.6, height: rect.height * 0.8))
        return path
    }
}

private struct IrregularShape3: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.5, y: 0))
        path.addCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.5),
            control1: CGPoint(x: rect.width * 0.9, y: rect.height * 0.1),
            control2: CGPoint(x: rect.width, y: rect.height * 0.3)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.5, y: rect.height),
            control1: CGPoint(x: rect.width, y: rect.height * 0.7),
            control2: CGPoint(x: rect.width * 0.8, y: rect.height)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: rect.height * 0.6),
            control1: CGPoint(x: rect.width * 0.2, y: rect.height),
            control2: CGPoint(x: 0, y: rect.height * 0.8)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.5, y: 0),
            control1: CGPoint(x: 0, y: rect.height * 0.2),
            control2: CGPoint(x: rect.width * 0.2, y: 0)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HomeView()
            .environmentObject(AppState())
    }
}
