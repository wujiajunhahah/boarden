import AVFoundation
import Foundation

@MainActor
final class CameraGuideViewModel: ObservableObject {
    enum AuthorizationState {
        case notDetermined
        case authorized
        case denied
    }

    enum RecognitionState: Equatable {
        case idle
        case scanning
        case recognized(Exhibit)
        case failed(String)
    }

    @Published var authorizationState: AuthorizationState = .notDetermined
    @Published var recognitionState: RecognitionState = .idle
    @Published var isSheetPresented = false

    private let exhibitMatcher = ExhibitMatchService()
    private let hapticsEnabled: Bool = true
    private var exhibits: [Exhibit] = []

    private var failureTask: Task<Void, Never>?

    func updateExhibits(_ exhibits: [Exhibit]) {
        self.exhibits = exhibits
    }

    func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorizationState = .authorized
        case .notDetermined:
            authorizationState = .notDetermined
        default:
            authorizationState = .denied
        }
    }

    func requestAccess() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        authorizationState = granted ? .authorized : .denied
    }

    func startScanning() {
        recognitionState = .scanning
        scheduleFailureHint()
    }

    func handleQRCode(_ code: String) {
        guard let exhibit = exhibits.first(where: { $0.id == code }) else {
            recognitionState = .failed("未识别到展品，可试试扫码或靠近展牌")
            Haptics.warning()
            return
        }
        recognitionState = .recognized(exhibit)
        isSheetPresented = true
        Haptics.success()
    }

    func handleRecognizedText(_ text: String) {
        guard let exhibit = exhibitMatcher.match(text: text, exhibits: exhibits) else {
            recognitionState = .failed("未识别到展品，可试试扫码或靠近展牌")
            return
        }
        recognitionState = .recognized(exhibit)
        isSheetPresented = true
        Haptics.success()
    }

    func simulateRecognition(_ exhibit: Exhibit) {
        recognitionState = .recognized(exhibit)
        isSheetPresented = true
        Haptics.success()
    }

    func reset() {
        recognitionState = .scanning
        scheduleFailureHint()
    }

    private func scheduleFailureHint() {
        failureTask?.cancel()
        failureTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, case .scanning = self.recognitionState else { return }
            self.recognitionState = .failed("未识别到展品，可试试扫码或靠近展牌")
        }
    }
}
