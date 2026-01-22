import AVFoundation
import Foundation

@MainActor
final class CameraGuideViewModel: ObservableObject {
    enum AuthorizationState {
        case notDetermined
        case authorized
        case denied
    }

    enum CaptureStage: Equatable {
        case signboard
        case artifact(exhibit: Exhibit)
        case done(exhibit: Exhibit, artifactURL: URL)
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
    @Published var captureStage: CaptureStage = .signboard
    @Published var isProcessing = false
    @Published var lastOCRSummary: OCRSummary?

    private let exhibitMatcher = ExhibitMatchService()
    private var exhibits: [Exhibit] = []
    private let ocrService: OCRServicing
    private let fallbackOCRService: OCRServicing = LocalOCRService()
    private let exhibitGenerator: ExhibitGenerating = ExhibitGenerationService()

    var onExhibitGenerated: (@MainActor @Sendable (Exhibit) -> Void)?

    private var failureTask: Task<Void, Never>?

    init(ocrService: OCRServicing? = nil) {
        if let ocrService {
            self.ocrService = ocrService
        } else if Secrets.shared.isValidZhipuKey {
            // 使用智谱多模态 OCR 服务
            self.ocrService = ZhipuOCRService()
            print("[CameraGuideViewModel] 使用智谱 OCR 服务")
        } else {
            // 降级到本地 OCR
            self.ocrService = LocalOCRService()
            print("[CameraGuideViewModel] 使用本地 OCR 服务")
        }
    }

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

    func handleSignboardPhoto(_ data: Data) {
        guard !isProcessing else { return }
        isProcessing = true
        recognitionState = .scanning
        failureTask?.cancel()

        Task {
            defer { isProcessing = false }

            let ocrText = try? await ocrService.recognize(imageData: data)
            let fallbackText = try? await fallbackOCRService.recognize(imageData: data)
            let mergedText = [ocrText?.text, fallbackText?.text].compactMap { $0 }.joined(separator: " ")

            let cleaned = mergedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else {
                recognitionState = .failed("未识别到展牌文字，请重新拍展牌")
                Haptics.warning()
                return
            }

            let summary = TextProcessing.summarize(cleaned)
            lastOCRSummary = summary

            do {
                if let generated = try await exhibitGenerator.generate(from: summary.rawText) {
                    let handler = onExhibitGenerated
                    Task { @MainActor in
                        handler?(generated)
                    }
                    recognitionState = .recognized(generated)
                    captureStage = .artifact(exhibit: generated)
                    isSheetPresented = true
                    Haptics.success()
                    return
                }
            } catch {
                if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
                    recognitionState = .failed("网络不可用，请连接后重试")
                    Haptics.warning()
                    return
                }
                if let genError = error as? ExhibitGenerationError {
                    recognitionState = .failed(genError.localizedDescription)
                    Haptics.warning()
                    return
                }
                recognitionState = .failed("生成展品失败，请稍后重试")
                Haptics.warning()
                return
            }

            if let exhibit = exhibitMatcher.match(text: mergedText, exhibits: exhibits) {
                recognitionState = .recognized(exhibit)
                captureStage = .artifact(exhibit: exhibit)
                isSheetPresented = true
                Haptics.success()
                return
            }

            recognitionState = .failed("已识别文字但未生成展品，请重新拍展牌")
            Haptics.warning()
        }
    }

    func handleArtifactPhoto(_ data: Data, saveURL: URL) {
        guard case let .artifact(exhibit) = captureStage else { return }
        do {
            try data.write(to: saveURL)
            captureStage = .done(exhibit: exhibit, artifactURL: saveURL)
            recognitionState = .recognized(exhibit)
        } catch {
            recognitionState = .failed("保存照片失败，请重试")
        }
    }

    func simulateRecognition(_ exhibit: Exhibit) {
        recognitionState = .recognized(exhibit)
        captureStage = .artifact(exhibit: exhibit)
        isSheetPresented = true
        Haptics.success()
    }

    func reset() {
        recognitionState = .scanning
        captureStage = .signboard
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
