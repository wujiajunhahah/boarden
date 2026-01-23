import Foundation

// MARK: - 智谱 AI 服务

/// 智谱多模态 OCR 服务
struct ZhipuOCRService: OCRServicing {
    func recognize(imageData: Data) async throws -> OCRResult? {
        guard let apiKey = Secrets.shared.zhipuApiKey else {
            return nil
        }

        let baseURL = Secrets.shared.zhipuBaseURL
        let model = Secrets.shared.zhipuOCRModel
        let endpoint = baseURL.appendingPathComponent("chat/completions")

        let imageBase64 = imageData.base64EncodedString()
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imageBase64)"]],
                        ["type": "text", "text": "请识别图片中的所有文字，只返回识别到的文字内容，不要添加任何解释或说明。"]
                    ]
                ]
            ],
            "temperature": 0.3
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            // 打印响应用于调试
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("[ZhipuOCR] 响应: \(json)")
            }

            guard let http = response as? HTTPURLResponse else {
                print("[ZhipuOCR] 无效的响应")
                return nil
            }

            print("[ZhipuOCR] 状态码: \(http.statusCode)")

            if http.statusCode == 401 {
                print("[ZhipuOCR] API Key 无效")
                return nil
            }

            guard (200...299).contains(http.statusCode) else {
                let errorStr = String(data: data, encoding: .utf8) ?? "Unknown"
                print("[ZhipuOCR] 错误响应: \(errorStr)")
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[ZhipuOCR] JSON 解析失败")
                return nil
            }

            let choices = json["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            let content = message?["content"] as? String ?? ""

            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            print("[ZhipuOCR] 识别结果: \(trimmed.prefix(100))")
            return trimmed.isEmpty ? nil : OCRResult(text: trimmed)
        } catch {
            print("[ZhipuOCR] 请求异常: \(error)")
            return nil
        }
    }
}

/// 智谱对话服务
protocol ZhipuChatServicing: Sendable {
    func generate(system: String, user: String) async throws -> String?
}

struct ZhipuChatService: ZhipuChatServicing {
    func generate(system: String, user: String) async throws -> String? {
        guard let apiKey = Secrets.shared.zhipuApiKey else {
            return nil
        }

        let endpoint = Secrets.shared.zhipuBaseURL.appendingPathComponent("chat/completions")
        let model = Secrets.shared.zhipuChatModel

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.4
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            // 打印响应用于调试
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("[ZhipuChat] 响应: \(json)")
            }

            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let errorStr = String(data: data, encoding: .utf8) ?? "Unknown"
                print("[ZhipuChat] 错误响应: \(errorStr)")
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            let choices = json["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            let text = message?["content"] as? String ?? ""

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            print("[ZhipuChat] 请求异常: \(error)")
            return nil
        }
    }
}

/// 智谱展品解说服务
struct ZhipuNarrationService: ExhibitNarrationServicing {
    private let service: ZhipuChatServicing = ZhipuChatService()

    func generate(title: String) async throws -> ExhibitNarration? {
        let system = "你是博物馆讲解员，输出中文、克制、清晰。"
        let user = "请为展品《\(title)》生成：1) 易读版 3-5 句 2) 详细版 6-10 句。用换行分隔，格式：易读版：... 详细版：..."

        guard let response = try await service.generate(system: system, user: user) else {
            return nil
        }

        let easy = extract(response, keyword: "易读版") ?? ""
        let detail = extract(response, keyword: "详细版") ?? ""

        if easy.isEmpty && detail.isEmpty {
            return nil
        }

        return ExhibitNarration(easyText: easy.isEmpty ? response : easy, detailText: detail.isEmpty ? response : detail)
    }

    private func extract(_ text: String, keyword: String) -> String? {
        guard let range = text.range(of: keyword) else { return nil }
        let after = text[range.upperBound...]
        let lines = after.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard let firstLine = lines.first, !firstLine.isEmpty else { return nil }
        return firstLine
    }
}

