import SwiftUI

@main
struct BroadenApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var permissionService = PermissionService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(permissionService)
                .task {
                    await appState.loadExhibits()

                    // 首次启动时请求权限
                    if permissionService.isFirstLaunch {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒延迟
                        await permissionService.requestAllPermissions()
                        
                        // 触发网络权限弹窗（发起一个简单的网络请求）
                        await triggerNetworkPermission()
                    }
                }
        }
    }
    
    /// 触发网络权限弹窗
    private func triggerNetworkPermission() async {
        // 发起一个简单的网络请求来触发系统的网络权限弹窗
        guard let url = URL(string: "https://www.apple.com") else { return }
        
        do {
            let (_, _) = try await URLSession.shared.data(from: url)
            print("[Network] 网络权限已获取")
        } catch {
            print("[Network] 网络请求失败（可能用户拒绝了权限）: \(error.localizedDescription)")
        }
    }
}
