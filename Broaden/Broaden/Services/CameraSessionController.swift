import AVFoundation
import Vision

final class CameraSessionController: NSObject {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let videoOutputQueue = DispatchQueue(label: "camera.video.output.queue")

    var onQRCodeDetected: (@MainActor @Sendable (String) -> Void)?
    var onTextDetected: (@MainActor @Sendable (String) -> Void)?

    var enableTextRecognition = false

    private var lastDetectionTime: Date = .distantPast
    private let detectionCooldown: TimeInterval = 1.5
    private var isProcessingText = false

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

            self.session.commitConfiguration()
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

    private func shouldHandleDetection() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastDetectionTime) > detectionCooldown else { return false }
        lastDetectionTime = now
        return true
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
        guard !isProcessingText else { return }
        guard shouldHandleDetection() else { return }
        isProcessingText = true

        let request = VNRecognizeTextRequest { [weak self] request, _ in
            defer { self?.isProcessingText = false }
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
