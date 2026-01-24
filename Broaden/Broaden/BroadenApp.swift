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
                    }
                }
        }
    }
}
