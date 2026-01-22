import Foundation

@MainActor
final class ExhibitDetailViewModel: ObservableObject {
    @Published var isFavorite = false
    @Published var showDetailText = false
    @Published var generatedEasyText: String?
    @Published var generatedDetailText: String?

    private let favoritesKey = "favoriteExhibitIds"
    private let narrationService: ExhibitNarrationServicing

    init(exhibitId: String, narrationService: ExhibitNarrationServicing? = nil) {
        if let narrationService {
            self.narrationService = narrationService
        } else if Secrets.shared.deepseekApiKey != nil {
            self.narrationService = DeepSeekNarrationService()
        } else {
            self.narrationService = DeepSeekNarrationService()
        }
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

    func loadGeneratedNarration(title: String) {
        guard Secrets.shared.deepseekApiKey != nil else { return }
        Task {
            do {
                if let narration = try await narrationService.generate(title: title) {
                    generatedEasyText = narration.easyText
                    generatedDetailText = narration.detailText
                }
            } catch {
                // Keep local text fallback.
            }
        }
    }
}
