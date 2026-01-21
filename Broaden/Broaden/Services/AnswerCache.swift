import Foundation

actor AnswerCache {
    private let directory: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        directory = (base ?? FileManager.default.temporaryDirectory).appendingPathComponent("AskCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func load(for request: AskRequest) -> AskResponse? {
        let url = cacheURL(for: request)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(AskResponse.self, from: data)
    }

    func save(_ response: AskResponse, for request: AskRequest) {
        let url = cacheURL(for: request)
        guard let data = try? encoder.encode(response) else { return }
        try? data.write(to: url)
    }

    private func cacheURL(for request: AskRequest) -> URL {
        let safeKey = request.exhibitId + "_" + request.question
        let hash = safeKey.data(using: .utf8)?.base64EncodedString() ?? UUID().uuidString
        return directory.appendingPathComponent(hash).appendingPathExtension("json")
    }
}
