import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

struct SubjectMaskingService: Sendable {
    private let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])

    /// 从图片中提取主体（去背景）
    /// - Parameter image: 原始图片
    /// - Returns: 去背景后的图片（透明背景）
    func extractSubject(from image: UIImage?) async -> UIImage? {
        guard let image else { return nil }

        // 处理图片方向
        guard let orientedImage = image.correctlyOrientedImage() else { return nil }
        guard let cgImage = orientedImage.cgImage else { return nil }

        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let result = self.performSegmentation(on: cgImage, scale: image.scale)
                continuation.resume(returning: result)
            }
        }
    }

    /// 执行主体分割
    private func performSegmentation(on cgImage: CGImage, scale: CGFloat) -> UIImage? {
        // 如果图片太大，先缩放以提高性能
        let maxDimension: CGFloat = 2048
        let workingImage: CGImage
        let workingScale: CGFloat

        if CGFloat(max(cgImage.width, cgImage.height)) > maxDimension {
            let scaleFactor = maxDimension / CGFloat(max(cgImage.width, cgImage.height))
            let newWidth = Int(CGFloat(cgImage.width) * scaleFactor)
            let newHeight = Int(CGFloat(cgImage.height) * scaleFactor)

            guard let context = CGContext(
                data: nil,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: cgImage.bitsPerComponent,
                bytesPerRow: 0,
                space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: cgImage.bitmapInfo.rawValue
            ) else {
                return nil
            }

            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

            guard let scaled = context.makeImage() else {
                return nil
            }

            workingImage = scaled
            workingScale = scaleFactor * scale
        } else {
            workingImage = cgImage
            workingScale = scale
        }

        // 创建 Vision 请求
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: workingImage, options: [:])

        do {
            try handler.perform([request])

            guard let observations = request.results, !observations.isEmpty else {
                print("[SubjectMasking] 未检测到主体")
                return nil
            }

            print("[SubjectMasking] 检测到 \(observations.count) 个主体")

            // 选择最佳主体（最大的）
            let bestObservation = selectLargestObservation(
                observations: observations,
                in: workingImage
            )

            guard let observation = bestObservation else {
                return nil
            }

            // 生成高质量蒙版
            let maskPixelBuffer = try observation.generateScaledMaskForImage(
                forInstances: observation.allInstances,  // 使用所有实例
                from: handler
            )

            // 应用蒙版并进行边缘优化
            if let result = applyMaskWithRefinement(
                to: workingImage,
                mask: maskPixelBuffer,
                scale: workingScale
            ) {
                // 裁剪透明区域
                if let cropped = cropTransparentAreas(from: result) {
                    return cropped
                }
                return result
            }

            return nil

        } catch {
            print("[SubjectMasking] 分割失败: \(error)")
            return nil
        }
    }

    /// 选择最大的主体（通常是最明显的前景物体）
    private func selectLargestObservation(
        observations: [VNInstanceMaskObservation],
        in image: CGImage
    ) -> VNInstanceMaskObservation? {
        var largest: VNInstanceMaskObservation?
        var maxArea: CGFloat = 0

        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        for observation in observations {
            guard let mask = try? observation.generateScaledMaskForImage(
                forInstances: IndexSet(integer: 0),
                from: handler
            ) else {
                continue
            }

            let width = CVPixelBufferGetWidth(mask)
            let height = CVPixelBufferGetHeight(mask)
            let area = CGFloat(width * height)

            if area > maxArea {
                maxArea = area
                largest = observation
            }
        }

        return largest
    }

    /// 应用蒙版并进行边缘优化，添加白色描边
    private func applyMaskWithRefinement(
        to cgImage: CGImage,
        mask: CVPixelBuffer,
        scale: CGFloat
    ) -> UIImage? {
        let inputImage = CIImage(cgImage: cgImage)
        let maskImage = CIImage(cvPixelBuffer: mask)

        // 1. 首先进行边缘羽化，让边缘更平滑
        let featherRadius: CGFloat = 1.5
        var refinedMask = maskImage

        if let featherFilter = CIFilter(name: "CIGaussianBlur") {
            featherFilter.setValue(maskImage, forKey: kCIInputImageKey)
            featherFilter.setValue(featherRadius, forKey: kCIInputRadiusKey)
            if let blurred = featherFilter.outputImage {
                refinedMask = blurred
            }
        }

        // 2. 应用蒙版去背景
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            return nil
        }

        blendFilter.setValue(inputImage, forKey: kCIInputImageKey)
        blendFilter.setValue(refinedMask, forKey: kCIInputMaskImageKey)
        blendFilter.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)

        guard let subjectOnlyImage = blendFilter.outputImage else {
            return nil
        }

        // 3. 添加白色描边（增加宽度使效果更明显）
        let strokeWidth: CGFloat = 6.0
        let strokeResult = addWhiteStroke(
            to: subjectOnlyImage,
            mask: refinedMask,
            strokeWidth: strokeWidth
        )

        let finalImage = strokeResult ?? subjectOnlyImage
        guard let resultCG = context.createCGImage(finalImage, from: finalImage.extent) else {
            return nil
        }

        return UIImage(cgImage: resultCG, scale: scale, orientation: .up)
    }

    /// 给主体添加白色描边
    private func addWhiteStroke(
        to image: CIImage,
        mask: CIImage,
        strokeWidth: CGFloat
    ) -> CIImage? {
        // 扩张蒙版创建描边区域
        guard let dilateFilter = CIFilter(name: "CIMorphologyMaximum") else {
            return nil
        }
        dilateFilter.setValue(mask, forKey: kCIInputImageKey)
        dilateFilter.setValue(strokeWidth, forKey: kCIInputRadiusKey)

        guard let dilatedMask = dilateFilter.outputImage else {
            return nil
        }

        // 计算描边区域（扩张蒙版 - 原蒙版）
        guard let subtractFilter = CIFilter(name: "CISubtractBlendMode") else {
            return nil
        }
        subtractFilter.setValue(dilatedMask, forKey: kCIInputImageKey)
        subtractFilter.setValue(mask, forKey: kCIInputBackgroundImageKey)

        guard let strokeRegionMask = subtractFilter.outputImage else {
            return nil
        }

        // 创建白色描边颜色
        guard let colorFilter = CIFilter(name: "CIConstantColorGenerator") else {
            return nil
        }
        colorFilter.setValue(CIVector(x: 1.0, y: 1.0, z: 1.0, w: 1.0), forKey: kCIInputColorKey)

        guard let strokeColorImage = colorFilter.outputImage else {
            return nil
        }

        // 将白色应用到描边区域
        guard let strokeBlendFilter = CIFilter(name: "CIBlendWithMask") else {
            return nil
        }
        strokeBlendFilter.setValue(strokeColorImage, forKey: kCIInputImageKey)
        strokeBlendFilter.setValue(strokeRegionMask, forKey: kCIInputMaskImageKey)

        guard let strokeLayer = strokeBlendFilter.outputImage else {
            return nil
        }

        // 合成：描边在下层，主体在上层
        guard let compositeFilter = CIFilter(name: "CISourceOverCompositing") else {
            return nil
        }
        compositeFilter.setValue(image, forKey: kCIInputImageKey)
        compositeFilter.setValue(strokeLayer, forKey: kCIInputBackgroundImageKey)

        return compositeFilter.outputImage
    }

    /// 裁剪透明区域，只保留主体部分
    private func cropTransparentAreas(from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return nil }
        let pixels = data.assumingMemoryBound(to: UInt32.self)

        // 查找非透明像素的边界
        var minX = width, minY = height, maxX = 0, maxY = 0
        let alphaMask: UInt32 = 0xFF000000

        for y in 0..<height {
            for x in 0..<width {
                let pixel = pixels[y * width + x]
                if pixel & alphaMask != 0 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }

        // 如果全是透明图像，返回原图
        if minX >= maxX || minY >= maxY {
            return image
        }

        // 添加少量边距以保留文物边缘（避免太贴边）
        let padding: Int = 10
        minX = max(0, minX - padding)
        minY = max(0, minY - padding)
        maxX = min(width - 1, maxX + padding)
        maxY = min(height - 1, maxY + padding)

        let contentWidth = maxX - minX + 1
        let contentHeight = maxY - minY + 1

        if let croppedCG = cgImage.cropping(
            to: CGRect(x: minX, y: minY, width: contentWidth, height: contentHeight)
        ) {
            return UIImage(cgImage: croppedCG, scale: image.scale, orientation: .up)
        }

        return image
    }
}

// MARK: - UIImage 方向修正扩展

extension UIImage {
    /// 返回考虑了 imageOrientation 的正确方向的 UIImage
    func correctlyOrientedImage() -> UIImage? {
        // 如果方向是正确的，直接返回
        if imageOrientation == .up {
            return self
        }

        guard let cgImage = cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height

        var transform = CGAffineTransform.identity

        switch imageOrientation {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: CGFloat(width), y: CGFloat(height))
            transform = transform.rotated(by: .pi)
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: CGFloat(height), y: 0)
            transform = transform.rotated(by: .pi / 2)
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0, y: CGFloat(width))
            transform = transform.rotated(by: -.pi / 2)
        case .up, .upMirrored:
            break
        @unknown default:
            break
        }

        // 处理镜像
        switch imageOrientation {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: CGFloat(width), y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: CGFloat(height), y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        default:
            break
        }

        // 计算旋转后的尺寸
        let newSize: CGSize
        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            newSize = CGSize(width: height, height: width)
        default:
            newSize = CGSize(width: width, height: width)
        }

        // 绘制旋转后的图片
        guard let context = CGContext(
            data: nil,
            width: Int(newSize.width),
            height: Int(newSize.height),
            bitsPerComponent: cgImage.bitsPerComponent,
            bytesPerRow: 0,
            space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: cgImage.bitmapInfo.rawValue
        ) else {
            return self
        }

        context.concatenate(transform)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let newCGImage = context.makeImage() else {
            return self
        }

        return UIImage(cgImage: newCGImage, scale: scale, orientation: .up)
    }
}
