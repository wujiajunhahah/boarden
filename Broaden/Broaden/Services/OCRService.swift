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

/// 已废弃的通义千问 OCR（保留用于兼容性，现在使用智谱）
struct QwenOCRService: OCRServicing {
    func recognize(imageData: Data) async throws -> OCRResult? {
        // 返回 nil，使用本地 OCR 作为回退
        return nil
    }
}
