import AVFoundation
import Photos
import CoreLocation
import SwiftUI

@MainActor
final class PermissionService: ObservableObject {
    enum PermissionType {
        case camera
        case photoLibrary
        case location

        var title: String {
            switch self {
            case .camera: return "相机权限"
            case .photoLibrary: return "相册权限"
            case .location: return "位置权限"
            }
        }

        var description: String {
            switch self {
            case .camera: return "扫描展品二维码或展牌文字"
            case .photoLibrary: return "从相册选择和保存照片"
            case .location: return "记录博物馆位置信息"
            }
        }

        var icon: String {
            switch self {
            case .camera: return "camera.fill"
            case .photoLibrary: return "photo.on.rectangle"
            case .location: return "location.fill"
            }
        }

        var systemName: String {
            switch self {
            case .camera: return "NSCameraUsageDescription"
            case .photoLibrary: return "NSPhotoLibraryUsageDescription"
            case .location: return "NSLocationWhenInUseUsageDescription"
            }
        }
    }

    enum PermissionStatus {
        case notDetermined
        case authorized
        case denied
    }

    @Published var cameraStatus: PermissionStatus = .notDetermined
    @Published var photoLibraryStatus: PermissionStatus = .notDetermined
    @Published var locationStatus: PermissionStatus = .notDetermined

    @Published var showDeniedAlert = false
    @Published var deniedPermissionType: PermissionType?

    private let locationManager = CLLocationManager()

    // 首次启动检查
    var isFirstLaunch: Bool {
        UserDefaults.standard.bool(forKey: "hasSeenOnboarding") == false
    }

    func markOnboardingSeen() {
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
    }

    // 检查所有权限状态
    func checkAllPermissions() {
        cameraStatus = checkPermission(.camera)
        photoLibraryStatus = checkPermission(.photoLibrary)
        locationStatus = checkPermission(.location)
    }

    // 请求单个权限
    func requestPermission(_ type: PermissionType) async {
        switch type {
        case .camera:
            await requestCameraPermission()
        case .photoLibrary:
            await requestPhotoLibraryPermission()
        case .location:
            await requestLocationPermission()
        }
    }

    // 请求所有权限
    func requestAllPermissions() async {
        await requestCameraPermission()
        await requestPhotoLibraryPermission()
        await requestLocationPermission()
    }

    // 检查是否所有权限都已授权
    var allPermissionsGranted: Bool {
        cameraStatus == .authorized &&
        photoLibraryStatus == .authorized &&
        locationStatus == .authorized
    }

    // 打开设置页面
    func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }

    // MARK: - Private Methods

    private func checkPermission(_ type: PermissionType) -> PermissionStatus {
        switch type {
        case .camera:
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: return .authorized
            case .denied, .restricted: return .denied
            default: return .notDetermined
            }

        case .photoLibrary:
            switch PHPhotoLibrary.authorizationStatus() {
            case .authorized, .limited: return .authorized
            case .denied, .restricted: return .denied
            default: return .notDetermined
            }

        case .location:
            switch locationManager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: return .authorized
            case .denied, .restricted: return .denied
            default: return .notDetermined
            }
        }
    }

    private func requestCameraPermission() async {
        let status = await AVCaptureDevice.requestAccess(for: .video)
        cameraStatus = status ? .authorized : .denied

        if !status {
            showDeniedAlert = true
            deniedPermissionType = .camera
        }
    }

    private func requestPhotoLibraryPermission() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        photoLibraryStatus = (status == .authorized || status == .limited) ? .authorized : .denied

        if photoLibraryStatus == .denied {
            showDeniedAlert = true
            deniedPermissionType = .photoLibrary
        }
    }

    private func requestLocationPermission() async {
        locationManager.requestWhenInUseAuthorization()
        // 位置权限是异步的，需要延迟检查
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
        locationStatus = checkPermission(.location)
    }
}
