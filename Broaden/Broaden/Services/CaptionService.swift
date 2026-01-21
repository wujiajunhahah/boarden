import Foundation

struct CaptionEntry: Identifiable, Sendable, Hashable {
    let id = UUID()
    let text: String
}

protocol CaptionProviding: Sendable {
    func loadCaptions(filename: String) -> [CaptionEntry]
}

struct CaptionService: CaptionProviding {
    func loadCaptions(filename: String) -> [CaptionEntry] {
        guard let url = Bundle.main.url(forResource: filename, withExtension: nil),
              let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .utf8) else {
            return []
        }
        return parseSRT(raw)
    }

    private func parseSRT(_ raw: String) -> [CaptionEntry] {
        let blocks = raw.components(separatedBy: "\n\n")
        var entries: [CaptionEntry] = []
        for block in blocks {
            let lines = block.split(separator: "\n")
            guard lines.count >= 3 else { continue }
            let textLines = lines.dropFirst(2)
            let text = textLines.joined(separator: " ")
            if !text.isEmpty {
                entries.append(CaptionEntry(text: text))
            }
        }
        return entries
    }
}
