import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

struct SubjectMaskingService: Sendable {
    private let context = CIContext()

    func extractSubject(from image: UIImage?) async -> UIImage? {
        guard let image else { return nil }
        guard let cgImage = image.cgImage else { return nil }

        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let orientation = CGImagePropertyOrientation(image.imageOrientation)
                let request = VNGenerateForegroundInstanceMaskRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
                let localContext = self.context
                let scale = image.scale
                let imageOrientation = image.imageOrientation

                let result: UIImage? = try? {
                    try handler.perform([request])
                    guard let observation = request.results?.first as? VNInstanceMaskObservation else { return nil }

                    // 使用正确的 API: generateScaledMaskForImage
                    let maskPixelBuffer = try observation.generateScaledMaskForImage(
                        forInstances: IndexSet(integer: 0),
                        from: handler
                    )

                    let inputImage = CIImage(cgImage: cgImage)
                    let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)
                    let background = CIImage(color: .clear).cropped(to: inputImage.extent)

                    let output = inputImage.applyingFilter(
                        "CIBlendWithMask",
                        parameters: [
                            kCIInputMaskImageKey: maskImage,
                            kCIInputBackgroundImageKey: background
                        ]
                    )

                    guard let resultCG = localContext.createCGImage(output, from: output.extent) else { return nil }
                    return UIImage(cgImage: resultCG, scale: scale, orientation: imageOrientation)
                }()

                continuation.resume(returning: result)
            }
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}
