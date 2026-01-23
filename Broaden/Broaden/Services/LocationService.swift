import CoreLocation
import Foundation
import MapKit

@MainActor
final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func fetchCurrentLocation() async -> LocationRecord? {
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            break
        default:
            return nil
        }

        guard let location = await requestLocation() else { return nil }
        return await reverseGeocode(location)
    }

    private func requestLocation() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            self.continuation?.resume(returning: nil)
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    private func reverseGeocode(_ location: CLLocation) async -> LocationRecord {
        // iOS 26+ 使用 MapKit 的 MKReverseGeocodingRequest
        if #available(iOS 26.0, *) {
            return await reverseGeocodeWithMapKit(location)
        } else {
            // iOS 25 及以下使用 CLGeocoder
            return await reverseGeocodeWithCoreLocation(location)
        }
    }
    
    /// iOS 26+ 使用 MapKit 的 MKReverseGeocodingRequest
    @available(iOS 26.0, *)
    private func reverseGeocodeWithMapKit(_ location: CLLocation) async -> LocationRecord {
        let coordinate = location.coordinate
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = nil
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 100,
            longitudinalMeters: 100
        )
        
        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()
            let mapItem = response.mapItems.first
            
            return LocationRecord(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                name: mapItem?.name ?? mapItem?.placemark.title,
                locality: mapItem?.placemark.locality,
                administrativeArea: mapItem?.placemark.administrativeArea,
                country: mapItem?.placemark.country,
                timestamp: Date()
            )
        } catch {
            // 如果 MapKit 失败，返回基本信息
            return LocationRecord(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                name: nil,
                locality: nil,
                administrativeArea: nil,
                country: nil,
                timestamp: Date()
            )
        }
    }
    
    /// iOS 25 及以下使用 CLGeocoder
    private func reverseGeocodeWithCoreLocation(_ location: CLLocation) async -> LocationRecord {
        let geocoder = CLGeocoder()
        let placemark = (try? await geocoder.reverseGeocodeLocation(location))?.first
        let name = placemark?.areasOfInterest?.first ?? placemark?.name
        return LocationRecord(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            name: name,
            locality: placemark?.locality,
            administrativeArea: placemark?.administrativeArea,
            country: placemark?.country,
            timestamp: Date()
        )
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        continuation?.resume(returning: locations.last)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(returning: nil)
        continuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            manager.requestLocation()
        } else if status == .denied || status == .restricted {
            continuation?.resume(returning: nil)
            continuation = nil
        }
    }
}
