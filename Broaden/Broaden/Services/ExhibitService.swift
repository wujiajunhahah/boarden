import Foundation

protocol ExhibitProviding: Sendable {
    func loadExhibits() async throws -> [Exhibit]
    func loadExhibit(by id: String) async throws -> Exhibit?
}

actor ExhibitService: ExhibitProviding {
    private let decoder = JSONDecoder()
    private var cached: [Exhibit]?

    func loadExhibits() async throws -> [Exhibit] {
        if let cached {
            return cached
        }
        guard let url = Bundle.main.url(forResource: "exhibits", withExtension: "json") else {
            throw ExhibitServiceError.missingData
        }
        let data = try Data(contentsOf: url)
        let exhibits = try decoder.decode([Exhibit].self, from: data)
        cached = exhibits
        return exhibits
    }

    func loadExhibit(by id: String) async throws -> Exhibit? {
        let exhibits = try await loadExhibits()
        return exhibits.first { $0.id == id }
    }
}

enum ExhibitServiceError: Error {
    case missingData
}
