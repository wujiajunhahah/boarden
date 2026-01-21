import Foundation

@MainActor
final class ExhibitDetailViewModel: ObservableObject {
    @Published var isFavorite = false
    @Published var showDetailText = false

    private let favoritesKey = "favoriteExhibitIds"

    init(exhibitId: String) {
        loadFavorite(exhibitId: exhibitId)
    }

    func toggleFavorite(exhibitId: String) {
        isFavorite.toggle()
        saveFavorite(exhibitId: exhibitId)
        Haptics.lightImpact()
    }

    private func loadFavorite(exhibitId: String) {
        let ids = UserDefaults.standard.array(forKey: favoritesKey) as? [String] ?? []
        isFavorite = ids.contains(exhibitId)
    }

    private func saveFavorite(exhibitId: String) {
        var ids = UserDefaults.standard.array(forKey: favoritesKey) as? [String] ?? []
        if isFavorite {
            ids.append(exhibitId)
        } else {
            ids.removeAll { $0 == exhibitId }
        }
        UserDefaults.standard.set(ids, forKey: favoritesKey)
    }
}
