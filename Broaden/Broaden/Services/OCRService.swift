import Foundation
import Vision
import UIKit

struct OCRResult: Sendable, Hashable {
    let text: String
}

protocol OCRServicing: Sendable {
    func recognize(imageData: Data) async throws -> OCRResult?
}

struct LocalOCRService: OCRServicing {
    func recognize(imageData: Data) async throws -> OCRResult? {
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            return nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                let rawLines = observations.compactMap { $0.topCandidates(1).first?.string }
                let filtered = rawLines
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { line in
                        // Keep lines that contain CJK or letters, drop mostly numeric noise.
                        let hasCJK = line.range(of: "[\\u4e00-\\u9fff]", options: .regularExpression) != nil
                        let hasLetters = line.range(of: "[A-Za-z]", options: .regularExpression) != nil
                        let digits = line.range(of: "^[0-9\\s.,:/-]+$", options: .regularExpression) != nil
                        return (hasCJK || hasLetters) && !digits && line.count >= 2
                    }
                let merged = filtered.joined(separator: " ")
                if merged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: OCRResult(text: merged))
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.minimumTextHeight = 0.02

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

struct QwenOCRService: OCRServicing {
    func recognize(imageData: Data) async throws -> OCRResult? {
        guard let apiKey = Secrets.shared.qwenApiKey else {
            return nil
        }

        let baseURL = Secrets.shared.qwenBaseURL
        let model = Secrets.shared.qwenOCRModel
        let endpoint = baseURL.appendingPathComponent("services/aigc/multimodal-generation/generation")

        let imageBase64 = imageData.base64EncodedString()
        let payload: [String: Any] = [
            "model": model,
            "input": [
                "messages": [
                    [
                        "role": "user",
                        "content": [
                            ["image": "data:image/jpeg;base64,\(imageBase64)"],
                            ["text": "请识别图片中的文字，只返回文字本身。"]
                        ]
                    ]
                ]
            ]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let output = json?["output"] as? [String: Any]
        let choices = output?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = message?["content"] as? [String: Any]
        let text = content?["text"] as? String ?? ""

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : OCRResult(text: trimmed)
    }
}
