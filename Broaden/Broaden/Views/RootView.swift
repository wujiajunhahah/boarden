import SwiftUI

enum AppTab: CaseIterable {
    case home
    case camera
    case profile
}

struct RootView: View {
    @State private var selectedTab: AppTab = .home
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景图片（相机界面除外）
                if selectedTab != .camera {
                    backgroundView
                        .ignoresSafeArea()
                }

                TabView(selection: $selectedTab) {
                    HomeView()
                        .tabItem {
                            Label("首页", systemImage: "house.fill")
                        }
                        .tag(AppTab.home)

                    CameraGuideView()
                        .tabItem {
                            Label("相机", systemImage: "camera.fill")
                        }
                        .tag(AppTab.camera)

                    SettingsView()
                        .tabItem {
                            Label("设置", systemImage: "gearshape.fill")
                        }
                        .tag(AppTab.profile)
                }
                .navigationDestination(item: $appState.pendingExhibitForDetail) { (exhibit: Exhibit) in
                    ExhibitDetailView(exhibit: exhibit)
                }
            }
        }
    }

    /// 背景图片视图
    private var backgroundView: some View {
        Group {
            if let backgroundImage = UIImage(named: "background-pattern") {
                Image(uiImage: backgroundImage)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.08)
            } else if let backgroundImage = UIImage(named: "AppIcon-1024") {
                // 使用 AppIcon 作为备用背景
                Image(uiImage: backgroundImage)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.05)
                    .blur(radius: 20)
            } else {
                // 渐变背景作为默认
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.95, blue: 0.97),
                        Color(red: 0.98, green: 0.98, blue: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }
}
