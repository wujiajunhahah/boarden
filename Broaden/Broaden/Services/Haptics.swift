import UIKit

struct Haptics {
    static func lightImpact() {
        Task { @MainActor in
            guard !UIAccessibility.isReduceMotionEnabled else { return }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
        }
    }

    static func success() {
        Task { @MainActor in
            guard !UIAccessibility.isReduceMotionEnabled else { return }
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        }
    }

    static func warning() {
        Task { @MainActor in
            guard !UIAccessibility.isReduceMotionEnabled else { return }
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.warning)
        }
    }
}
