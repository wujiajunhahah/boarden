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
        // 不再自动显示失败提示，让用户自然操作
        // scheduleFailureHint()
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
        // 不再自动显示失败提示，让用户自然操作
        // scheduleFailureHint()
    }
    
    /// 进入直接拍摄模式，取消失败提示定时器
    func enterDirectCaptureMode() {
        failureTask?.cancel()
        failureTask = nil
        recognitionState = .idle
    }
    
    /// 直接从图片生成展品信息（跳过展牌识别）
    func generateExhibitFromImage(_ data: Data) async throws -> Exhibit? {
        // 使用智谱视觉模型识别图片中的物体
        let ocrResult = try? await ocrService.recognize(imageData: data)
        
        guard let text = ocrResult?.text, !text.isEmpty else {
            // 如果 OCR 没有识别到文字，尝试让模型直接描述图片内容
            return try await generateExhibitFromImageDescription(data)
        }
        
        // 使用识别到的文字生成展品
        return try await exhibitGenerator.generate(from: text)
    }
    
    /// 使用图片描述生成展品（当 OCR 无法识别文字时）
    private func generateExhibitFromImageDescription(_ data: Data) async throws -> Exhibit? {
        guard Secrets.shared.isValidZhipuKey else {
            throw ExhibitGenerationError.missingAPIKey
        }
        
        // 使用智谱视觉模型描述图片内容
        let base64Image = data.base64EncodedString()
        let chatService = ZhipuChatService()
        
        let system = """
        你是一个展馆的展品识别专家。请仔细观察图片中的主要物体，生成详细的描述信息。
        输出严格 JSON 格式：
        {
          "name": "展品名称",
          "category": "展品类别（如：工艺品、日用品、艺术品、食品等）",
          "description": "展品详细描述（50-100字）",
          "features": ["展品特征1", "展品特征2", "展品特征3"]
        }
        """
        
        let user = "请识别并描述这张图片中的主要物体。"
        
        guard let response = try await chatService.generateWithImage(system: system, user: user, imageBase64: base64Image) else {
            return nil
        }
        
        // 解析响应并生成展品
        return parseImageDescriptionToExhibit(response)
    }
    
    /// 解析图片描述生成展品
    private func parseImageDescriptionToExhibit(_ response: String) -> Exhibit? {
        // 提取 JSON
        var jsonString = response
        if let startRange = response.range(of: "{"),
           let endRange = response.range(of: "}", options: .backwards) {
            jsonString = String(response[startRange.lowerBound...endRange.upperBound])
        }
        
        guard let data = jsonString.data(using: .utf8) else { return nil }
        
        struct ImageDescription: Codable {
            let name: String
            let category: String?
            let description: String
            let features: [String]?
        }
        
        guard let desc = try? JSONDecoder().decode(ImageDescription.self, from: data) else {
            return nil
        }
        
        // 生成唯一 ID（使用 UUID 确保不会重复）
        let id = "EXH-\(UUID().uuidString.prefix(8))"
        
        // 生成术语卡片
        var glossary: [GlossaryItem] = []
        if let features = desc.features {
            glossary = features.prefix(3).map { feature in
                GlossaryItem(term: feature, def: "该物体的特征之一")
            }
        }
        
        return Exhibit(
            id: id,
            title: desc.name,
            shortIntro: desc.description,
            easyText: "这是一个\(desc.category ?? "物品")，名为\(desc.name)。\(desc.description)",
            detailText: desc.description,
            glossary: glossary,
            media: ExhibitMedia(signVideoFilename: "sign_demo.mp4", captionsVttOrSrtFilename: "captions_demo.srt"),
            references: []
        )
    }
    
    /// 完成直接拍摄流程
    func completeDirectCapture(exhibit: Exhibit, artifactURL: URL) {
        captureStage = .done(exhibit: exhibit, artifactURL: artifactURL)
        recognitionState = .recognized(exhibit)
        isSheetPresented = true
        Haptics.success()
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
