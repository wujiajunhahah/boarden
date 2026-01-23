import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var exhibits: [Exhibit] = []
    @Published var recentExhibitIds: [String] = []
    @Published private(set) var artifactPhotoURLs: [String: URL] = [:]
    @Published private(set) var exhibitLocations: [String: LocationRecord] = [:]
    
    /// 待跳转的展品详情（用于导航）
    @Published var pendingExhibitForDetail: Exhibit?

    private let exhibitService: ExhibitProviding
    private let recentsKey = "recentExhibitIds"
    private let artifactKey = "artifactPhotoURLs"
    private let locationKey = "exhibitLocations"
    private let locationService = LocationService()

    init(exhibitService: ExhibitProviding = ExhibitService()) {
        self.exhibitService = exhibitService
        loadRecents()
        loadArtifacts()
        loadLocations()
    }

    func loadExhibits() async {
        do {
            exhibits = try await exhibitService.loadExhibits()
        } catch {
            exhibits = []
        }
    }

    func exhibit(by id: String) -> Exhibit? {
        exhibits.first { $0.id == id }
    }

    func upsertExhibit(_ exhibit: Exhibit) {
        if let index = exhibits.firstIndex(where: { $0.id == exhibit.id }) {
            exhibits[index] = exhibit
        } else {
            exhibits.insert(exhibit, at: 0)
        }
    }

    func addRecent(exhibit: Exhibit) {
        recentExhibitIds.removeAll { $0 == exhibit.id }
        recentExhibitIds.insert(exhibit.id, at: 0)
        if recentExhibitIds.count > 10 {
            recentExhibitIds = Array(recentExhibitIds.prefix(10))
        }
        saveRecents()
    }

    private func loadRecents() {
        if let data = UserDefaults.standard.data(forKey: recentsKey),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            recentExhibitIds = ids
        }
    }

    private func saveRecents() {
        if let data = try? JSONEncoder().encode(recentExhibitIds) {
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }

    func saveArtifactPhoto(data: Data, exhibitId: String) -> URL? {
        let filename = "artifact_\(exhibitId)_\(UUID().uuidString).jpg"
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let url = folder?.appendingPathComponent(filename) else { return nil }
        do {
            try data.write(to: url)
            artifactPhotoURLs[exhibitId] = url
            saveArtifacts()
            return url
        } catch {
            return nil
        }
    }

    func artifactPhotoURL(for exhibitId: String) -> URL? {
        artifactPhotoURLs[exhibitId]
    }

    func captureLocation(for exhibitId: String) async {
        if let record = await locationService.fetchCurrentLocation() {
            exhibitLocations[exhibitId] = record
            saveLocations()
        }
    }

    func locationRecord(for exhibitId: String) -> LocationRecord? {
        exhibitLocations[exhibitId]
    }

    private func loadArtifacts() {
        if let data = UserDefaults.standard.data(forKey: artifactKey),
           let entries = try? JSONDecoder().decode([String: String].self, from: data) {
            var urls: [String: URL] = [:]
            for (key, value) in entries {
                if let url = URL(string: value) {
                    urls[key] = url
                }
            }
            artifactPhotoURLs = urls
        }
    }

    private func saveArtifacts() {
        let entries = artifactPhotoURLs.mapValues { $0.absoluteString }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: artifactKey)
        }
    }

    private func loadLocations() {
        if let data = UserDefaults.standard.data(forKey: locationKey),
           let entries = try? JSONDecoder().decode([String: LocationRecord].self, from: data) {
            exhibitLocations = entries
        }
    }

    private func saveLocations() {
        if let data = try? JSONEncoder().encode(exhibitLocations) {
            UserDefaults.standard.set(data, forKey: locationKey)
        }
    }
}
