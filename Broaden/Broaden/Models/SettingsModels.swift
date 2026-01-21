import Foundation

enum CaptionSize: String, CaseIterable, Identifiable, Codable, Sendable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        }
    }
}

enum RecognitionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case qrOnly
    case qrAndText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qrOnly: return "仅二维码"
        case .qrAndText: return "二维码 + 文字识别"
        }
    }
}
