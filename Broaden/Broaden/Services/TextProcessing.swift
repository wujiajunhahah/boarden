import Foundation

struct OCRSummary: Sendable, Hashable {
    let title: String
    let dateText: String?
    let intro: String
    let rawText: String
}

struct TextProcessing {
    static func summarize(_ raw: String) -> OCRSummary { 
        let lines = raw
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let title = pickTitle(from: lines, fallback: raw)
        let dateText = pickDate(from: lines)
        let intro = pickIntro(from: lines, excluding: title)

        return OCRSummary(
            title: title,
            dateText: dateText,
            intro: intro,
            rawText: raw
        )
    }

    private static func pickTitle(from lines: [String], fallback: String) -> String {
        if lines.isEmpty { return String(fallback.prefix(16)) }
        // Prefer the shortest line with CJK and reasonable length.
        let candidates = lines.filter { line in
            let hasCJK = line.range(of: "[\\u{4E00}-\\u{9FFF}]", options: .regularExpression) != nil
            return hasCJK && line.count >= 2 && line.count <= 20
        }
        if let best = candidates.sorted(by: { $0.count < $1.count }).first {
            return best
        }
        return lines.first ?? String(fallback.prefix(16))
    }

    private static func pickDate(from lines: [String]) -> String? {
        let patterns = [
            #"(\d{3,4})\s*年"#,
            #"(公元|约|约为|约公元)\s*\d+"#,
            #"(\d{1,2})\s*世纪"#,
            #"(商|周|秦|汉|唐|宋|元|明|清)代"#
        ]
        for line in lines {
            for pattern in patterns {
                if line.range(of: pattern, options: .regularExpression) != nil {
                    return line
                }
            }
        }
        return nil
    }

    private static func pickIntro(from lines: [String], excluding title: String) -> String {
        let filtered = lines.filter { $0 != title }
        let joined = filtered.joined(separator: " ")
        if joined.isEmpty { return "暂无简介" }
        return String(joined.prefix(160))
    }
}
