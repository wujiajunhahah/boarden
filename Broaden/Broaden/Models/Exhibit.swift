import Foundation

struct Exhibit: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let title: String
    let shortIntro: String
    let easyText: String
    let detailText: String
    let glossary: [GlossaryItem]
    let media: ExhibitMedia
    let references: [ReferenceSnippet]
}

struct GlossaryItem: Codable, Sendable, Hashable {
    let term: String
    let def: String
}

struct ExhibitMedia: Codable, Sendable, Hashable {
    let signVideoFilename: String
    let captionsVttOrSrtFilename: String
}

struct ReferenceSnippet: Codable, Sendable, Hashable {
    let refId: String
    let snippet: String
}
