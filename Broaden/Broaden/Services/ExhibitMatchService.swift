import Foundation

struct ExhibitMatchService: Sendable {
    func match(text: String, exhibits: [Exhibit]) -> Exhibit? {
        let normalized = normalize(text)
        let tokens = normalized.split(separator: " ").map(String.init)
        for exhibit in exhibits {
            let title = normalize(exhibit.title)
            if title.contains(normalized) || normalized.contains(title) {
                return exhibit
            }
            for token in tokens where token.count >= 2 {
                if title.contains(token) {
                    return exhibit
                }
            }
        }
        return nil
    }

    private func normalize(_ string: String) -> String {
        string
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
