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
