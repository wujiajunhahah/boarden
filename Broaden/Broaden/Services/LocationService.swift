import CoreLocation
import Foundation
import MapKit

@MainActor
final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func fetchCurrentLocation() async -> LocationRecord? {
        var status = manager.authorizationStatus
        
        // 如果权限未确定，请求权限并等待用户响应
        if status == .notDetermined {
            status = await requestAuthorization()
        }
        
        // 检查是否有权限
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            print("[LocationService] 位置权限未授予，状态: \(status.rawValue)")
            return nil
        }

        guard let location = await requestLocation() else {
            print("[LocationService] 无法获取位置")
            return nil
        }
        
        print("[LocationService] 获取到位置: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        return await reverseGeocode(location)
    }
    
    /// 请求位置权限并等待用户响应
    private func requestAuthorization() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            self.authContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    private func requestLocation() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            self.locationContinuation?.resume(returning: nil)
            self.locationContinuation = continuation
            manager.requestLocation()
        }
    }

    /// 使用 CLGeocoder 进行反向地理编码（所有 iOS 版本通用）
    private func reverseGeocode(_ location: CLLocation) async -> LocationRecord {
        let geocoder = CLGeocoder()
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            let placemark = placemarks.first
            
            // 优先使用兴趣点名称，其次是地点名称
            let name = placemark?.areasOfInterest?.first ?? placemark?.name
            
            let record = LocationRecord(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                name: name,
                locality: placemark?.locality,
                administrativeArea: placemark?.administrativeArea,
                country: placemark?.country,
                timestamp: Date()
            )
            
            print("[LocationService] 反向地理编码成功: \(record.displayName)")
            return record
            
        } catch {
            print("[LocationService] 反向地理编码失败: \(error.localizedDescription)")
            // 即使反向地理编码失败，也返回带有经纬度的记录
            return LocationRecord(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                name: nil,
                locality: nil,
                administrativeArea: nil,
                country: nil,
                timestamp: Date()
            )
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locationContinuation?.resume(returning: locations.last)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[LocationService] 位置请求失败: \(error.localizedDescription)")
        locationContinuation?.resume(returning: nil)
        locationContinuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        
        // 如果正在等待授权响应，返回新的授权状态
        if let authContinuation = authContinuation {
            // 只有当用户做出选择后才返回（不是 notDetermined）
            if status != .notDetermined {
                authContinuation.resume(returning: status)
                self.authContinuation = nil
            }
        }
        
        // 如果已授权且有等待中的位置请求，触发位置更新
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            if locationContinuation != nil {
                manager.requestLocation()
            }
        } else if status == .denied || status == .restricted {
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
        }
    }
}
