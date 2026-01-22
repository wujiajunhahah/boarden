import SwiftUI

enum AppTab: CaseIterable {
    case home
    case camera
    case profile
}

struct RootView: View {
    @State private var selectedTab: AppTab = .home

    var body: some View {
        ZStack {
            switch selectedTab {
            case .home:
                NavigationStack {
                    HomeView(selectedTab: $selectedTab)
                }
            case .camera:
                NavigationStack {
                    CameraGuideView()
                }
            case .profile:
                NavigationStack {
                    ProfileView()
                }
            }
        }
    }
}

// MARK: - Profile View (Placeholder)
struct ProfileView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("我的")
                    .font(.title.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()

                Text("用户资料页面即将推出")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("")
        .navigationBarHidden(true)
    }
}
