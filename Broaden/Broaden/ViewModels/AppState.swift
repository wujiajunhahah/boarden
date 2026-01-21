import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var exhibits: [Exhibit] = []
    @Published var recentExhibitIds: [String] = []

    private let exhibitService: ExhibitProviding
    private let recentsKey = "recentExhibitIds"

    init(exhibitService: ExhibitProviding = ExhibitService()) {
        self.exhibitService = exhibitService
        loadRecents()
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
}
