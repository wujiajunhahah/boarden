import Foundation

struct DeepSeekResponse: Sendable, Hashable {
    let text: String
}

protocol DeepSeekServicing: Sendable {
    func generate(system: String, user: String) async throws -> DeepSeekResponse?
}

struct DeepSeekService: DeepSeekServicing {
    func generate(system: String, user: String) async throws -> DeepSeekResponse? {
        // DeepSeek 已废弃，现在使用智谱 AI
        // 返回 nil 使调用者使用回退方案
        return nil
    }
}
