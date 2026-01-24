import AVFoundation
import Vision

final class CameraSessionController: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let videoOutputQueue = DispatchQueue(label: "camera.video.output.queue")
    private let stateQueue = DispatchQueue(label: "camera.state.queue")

    var onQRCodeDetected: (@MainActor @Sendable (String) -> Void)?
    var onTextDetected: (@MainActor @Sendable (String) -> Void)?
    var onPhotoCaptured: (@MainActor @Sendable (Data) -> Void)?

    var enableTextRecognition = false
    private let photoOutput = AVCapturePhotoOutput()
    private var videoDevice: AVCaptureDevice?

    private var lastDetectionTime: Date = .distantPast
    private let detectionCooldown: TimeInterval = 1.5
    private var isProcessingText = false
    
    // 缩放相关
    private var currentZoomFactor: CGFloat = 1.0
    private var lastZoomFactor: CGFloat = 1.0

    func configure() {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            self.videoDevice = device

            let metadataOutput = AVCaptureMetadataOutput()
            if self.session.canAddOutput(metadataOutput) {
                self.session.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = [.qr]
            }

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.alwaysDiscardsLateVideoFrames = true
            if self.session.canAddOutput(videoOutput) {
                self.session.addOutput(videoOutput)
                videoOutput.setSampleBufferDelegate(self, queue: self.videoOutputQueue)
            }

            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }

            self.session.commitConfiguration()
        }
    }
    
    // MARK: - Zoom Control
    
    /// 获取最大缩放倍数
    var maxZoomFactor: CGFloat {
        guard let device = videoDevice else { return 5.0 }
        return min(device.activeFormat.videoMaxZoomFactor, 10.0)
    }
    
    /// 获取最小缩放倍数
    var minZoomFactor: CGFloat {
        return 1.0
    }
    
    /// 开始缩放手势
    func beginZoom() {
        lastZoomFactor = currentZoomFactor
    }
    
    /// 更新缩放倍数
    func updateZoom(scale: CGFloat) {
        guard let device = videoDevice else { return }
        
        let newZoomFactor = lastZoomFactor * scale
        let clampedZoom = max(minZoomFactor, min(newZoomFactor, maxZoomFactor))
        
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clampedZoom
                device.unlockForConfiguration()
                self.currentZoomFactor = clampedZoom
            } catch {
                print("[Camera] 缩放失败: \(error.localizedDescription)")
            }
        }
    }
    
    /// 重置缩放
    func resetZoom() {
        guard let device = videoDevice else { return }
        
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = 1.0
                device.unlockForConfiguration()
                self.currentZoomFactor = 1.0
                self.lastZoomFactor = 1.0
            } catch {
                print("[Camera] 重置缩放失败: \(error.localizedDescription)")
            }
        }
    }

    func start() {
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func capturePhoto() {
        sessionQueue.async {
            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func shouldHandleDetection() -> Bool {
        stateQueue.sync {
            let now = Date()
            guard now.timeIntervalSince(lastDetectionTime) > detectionCooldown else { return false }
            lastDetectionTime = now
            return true
        }
    }

    private func beginTextProcessingIfNeeded() -> Bool {
        stateQueue.sync {
            guard !isProcessingText else { return false }
            isProcessingText = true
            return true
        }
    }

    private func endTextProcessing() {
        stateQueue.async {
            self.isProcessingText = false
        }
    }
}

extension CameraSessionController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard shouldHandleDetection() else { return }
        for object in metadataObjects {
            if let readable = object as? AVMetadataMachineReadableCodeObject,
               readable.type == .qr,
               let value = readable.stringValue {
                let handler = onQRCodeDetected
                Task { @MainActor in
                    handler?(value)
                }
                break
            }
        }
    }
}

extension CameraSessionController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard enableTextRecognition else { return }
        guard beginTextProcessingIfNeeded() else { return }
        guard shouldHandleDetection() else { return }

        let request = VNRecognizeTextRequest { [weak self] request, _ in
            self?.endTextProcessing()
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            let texts = observations.compactMap { $0.topCandidates(1).first?.string }
            let merged = texts.joined(separator: " ")
            guard !merged.isEmpty else { return }
            let handler = self?.onTextDetected
            Task { @MainActor in
                handler?(merged)
            }
        }
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.02

        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up)
        try? handler.perform([request])
    }
}

extension CameraSessionController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        let handler = onPhotoCaptured
        Task { @MainActor in
            handler?(data)
        }
    }
}
