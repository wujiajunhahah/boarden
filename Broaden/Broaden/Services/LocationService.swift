import CoreLocation
import Foundation

@MainActor
final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
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
