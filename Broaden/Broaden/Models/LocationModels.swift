import Foundation

struct LocationRecord: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let name: String?
    let locality: String?
    let administrativeArea: String?
    let country: String?
    let timestamp: Date

    var displayName: String {
        if let name, !name.isEmpty {
            return name
        }
        var parts: [String] = []
        if let locality, !locality.isEmpty { parts.append(locality) }
        if let administrativeArea, !administrativeArea.isEmpty { parts.append(administrativeArea) }
        if let country, !country.isEmpty { parts.append(country) }
        return parts.isEmpty ? "未知位置" : parts.joined(separator: " · ")
    }
}
