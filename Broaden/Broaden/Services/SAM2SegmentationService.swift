import CoreImage
import UIKit
import Vision
import Metal

/// 智能主体提取服务 - 自动识别图像中的主体并生成贴纸效果
@MainActor
final class SAM2SegmentationService: ObservableObject {
    static let shared = SAM2SegmentationService()

    @Published var isProcessing = false
    @Published var lastMask: UIImage?

    // 贴纸效果配置
    struct StickerStyle {
        var strokeColor: UIColor = .red  // 🔴 调试用红色，可看到描边位置
        var strokeWidth: CGFloat = 20  // 增加描边宽度让效果更明显
        var shadowColor: UIColor = UIColor(white: 0, alpha: 0.3)
        var shadowOffset: CGSize = CGSize(width: 0, height: 4)
        var shadowBlur: CGFloat = 8
        var enableStroke = true
        var enableShadow = true

        static let `default` = StickerStyle()
        static let bold = StickerStyle(
            strokeColor: .white,
            strokeWidth: 18,
            shadowColor: UIColor(white: 0, alpha: 0.5),
            shadowOffset: CGSize(width: 0, height: 6),
            shadowBlur: 12
        )
    }

    private var metalDevice: MTLDevice?
    private var commandQueue: MTLCommandQueue?

    private init() {
        self.metalDevice = MTLCreateSystemDefaultDevice()
        self.commandQueue = metalDevice?.makeCommandQueue()
    }

    /// 自动提取图像中的主体（最明显的物体）
    /// - Parameters:
    ///   - image: 原始图像
    ///   - style: 贴纸效果样式
    /// - Returns: 分割后的图像（背景透明 + 描边效果）
    func extractPrimarySubject(
        from image: UIImage?,
        style: StickerStyle = .default
    ) async -> UIImage? {
        guard let image else { return nil }
        return await segmentWithPoint(image: image, point: CGPoint(x: 0.5, y: 0.5), style: style)
    }

    /// 点选分割：用户点击图像上的点来分割物体
    /// - Parameters:
    ///   - image: 原始图像
    ///   - point: 用户点击的点（归一化坐标 0-1），如果是中心点会自动选择最大主体
    ///   - style: 贴纸效果样式
    /// - Returns: 分割后的图像（背景透明 + 描边效果）
    func segmentWithPoint(
        image: UIImage,
        point: CGPoint,
        style: StickerStyle = .default
    ) async -> UIImage? {
        print("[SAM2Service] segmentWithPoint 开始，point: \(point), style: enableStroke=\(style.enableStroke), enableShadow=\(style.enableShadow)")
        isProcessing = true
        defer { isProcessing = false }

        guard let result = await segmentWithVisionRequest(image: image, point: point, style: style) else {
            print("[SAM2Service] segmentWithVisionRequest 返回 nil")
            return nil
        }

        lastMask = result
        print("[SAM2Service] ✅ 分割成功，返回结果")
        return result
    }

    /// 使用 Vision 框架进行智能分割 + 贴纸效果
    private func segmentWithVisionRequest(
        image: UIImage,
        point: CGPoint,
        style: StickerStyle
    ) async -> UIImage? {
        // 考虑 UIImage 的方向信息，正确旋转图片
        guard let correctedCGImage = image.correctlyOrientedImage()?.cgImage else {
            print("[SAM2Service] ❌ 无法获取正确方向的 CGImage")
            return nil
        }

        print("[SAM2Service] 图像尺寸: \(correctedCGImage.width) x \(correctedCGImage.height), 原始方向: \(image.imageOrientation.rawValue)")

        // 如果图片太大，先缩放以提高性能
        let maxDimension: CGFloat = 2048
        let workingImage: CGImage
        let workingScale: CGFloat

        if CGFloat(max(correctedCGImage.width, correctedCGImage.height)) > maxDimension {
            print("[SAM2Service] 图片过大，先缩放再进行 Vision 分割")
            let scaleFactor = maxDimension / CGFloat(max(correctedCGImage.width, correctedCGImage.height))
            let newWidth = Int(CGFloat(correctedCGImage.width) * scaleFactor)
            let newHeight = Int(CGFloat(correctedCGImage.height) * scaleFactor)

            guard let context = CGContext(
                data: nil,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: correctedCGImage.bitsPerComponent,
                bytesPerRow: 0,
                space: correctedCGImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: correctedCGImage.bitmapInfo.rawValue
            ) else {
                print("[SAM2Service] ❌ 创建缩放 CGContext 失败")
                return nil
            }

            context.interpolationQuality = .high
            context.draw(correctedCGImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

            guard let scaled = context.makeImage() else {
                print("[SAM2Service] ❌ 缩放图片失败")
                return nil
            }

            workingImage = scaled
            workingScale = scaleFactor
            print("[SAM2Service] ✅ 预缩放完成: \(newWidth) x \(newHeight)")
        } else {
            workingImage = correctedCGImage
            workingScale = 1.0
        }

        // 使用 VNGenerateForegroundInstanceMaskRequest
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: workingImage, options: [:])

        do {
            print("[SAM2Service] 执行 Vision 请求...")
            try handler.perform([request])

            guard let observations = request.results, !observations.isEmpty else {
                print("[SAM2Service] ❌ 未检测到主体 (request.results 为空)")
                return nil
            }

            print("[SAM2Service] ✅ 检测到 \(observations.count) 个主体")

            // 自动选择最明显的主体（最大或最接近中心的）
            let selectedObservation = selectBestObservation(
                observations: observations,
                for: point,
                in: workingImage
            )

            guard let observation = selectedObservation else {
                print("[SAM2Service] ❌ 无法选择最佳主体")
                return nil
            }

            print("[SAM2Service] ✅ 已选择最佳主体")

            // 生成蒙版（使用 allInstances 合并所有检测到的主体）
            // 参考：https://artemnovichkov.com/blog/remove-background-from-image-in-swiftui
            let maskPixelBuffer = try observation.generateScaledMaskForImage(
                forInstances: observation.allInstances,
                from: handler
            )

            print("[SAM2Service] ✅ 蒙版生成成功，尺寸: \(CVPixelBufferGetWidth(maskPixelBuffer)) x \(CVPixelBufferGetHeight(maskPixelBuffer))")

            // 应用贴纸效果（描边 + 阴影）
            print("[SAM2Service] 应用贴纸效果...")
            let result = applyStickerEffect(
                to: workingImage,
                mask: maskPixelBuffer,
                scale: image.scale * workingScale,
                style: style
            )

            if result != nil {
                print("[SAM2Service] ✅ 贴纸效果应用成功")
            } else {
                print("[SAM2Service] ❌ 贴纸效果应用失败")
            }

            return result

        } catch {
            print("[SAM2Service] ❌ 分割失败: \(error)")
            return nil
        }
    }

    /// 选择最佳的主体实例
    /// - 如果是中心点，选择最大的主体
    /// - 如果是特定点，选择最接近该点的主体
    private func selectBestObservation(
        observations: [VNInstanceMaskObservation],
        for point: CGPoint,
        in image: CGImage
    ) -> VNInstanceMaskObservation? {
        // 如果是中心点（0.5, 0.5），选择最大的主体
        if abs(point.x - 0.5) < 0.01 && abs(point.y - 0.5) < 0.01 {
            return selectLargestObservation(observations: observations, in: image)
        }

        // 否则选择最接近点击点的主体
        return selectClosestObservation(observations: observations, to: point, in: image)
    }

    /// 选择最大的主体（通常是最明显的前景物体）
    private func selectLargestObservation(
        observations: [VNInstanceMaskObservation],
        in image: CGImage
    ) -> VNInstanceMaskObservation? {
        var largest: VNInstanceMaskObservation?
        var maxArea: CGFloat = 0

        for observation in observations {
            guard let mask = try? observation.generateScaledMaskForImage(
                forInstances: IndexSet(integer: 0),
                from: VNImageRequestHandler(cgImage: image, options: [:])
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

    /// 选择最接近点击点的主体
    private func selectClosestObservation(
        observations: [VNInstanceMaskObservation],
        to point: CGPoint,
        in image: CGImage
    ) -> VNInstanceMaskObservation? {
        let pixelPoint = CGPoint(
            x: point.x * CGFloat(image.width),
            y: point.y * CGFloat(image.height)
        )

        var closest: VNInstanceMaskObservation?
        var minDistance: CGFloat = .infinity

        for observation in observations {
            guard let mask = try? observation.generateScaledMaskForImage(
                forInstances: IndexSet(integer: 0),
                from: VNImageRequestHandler(cgImage: image, options: [:])
            ) else {
                continue
            }

            let maskWidth = CVPixelBufferGetWidth(mask)
            let maskHeight = CVPixelBufferGetHeight(mask)
            let centerX = CGFloat(maskWidth) / 2
            let centerY = CGFloat(maskHeight) / 2

            let distance = sqrt(
                pow(pixelPoint.x - centerX, 2) +
                pow(pixelPoint.y - centerY, 2)
            )

            if distance < minDistance {
                minDistance = distance
                closest = observation
            }
        }

        return minDistance < min(CGFloat(image.width), CGFloat(image.height)) * 0.4 ? closest : nil
    }

    /// 应用贴纸效果（去背景 + 白色描边）
    /// 使用 CoreImage 滤镜实现去背景，然后添加贴纸描边
    private func applyStickerEffect(
        to cgImage: CGImage,
        mask: CVPixelBuffer,
        scale: CGFloat,
        style: StickerStyle
    ) -> UIImage? {
        print("[SAM2Service] applyStickerEffect 开始，原图尺寸: \(cgImage.width) x \(cgImage.height), enableStroke: \(style.enableStroke)")

        let inputImage = CIImage(cgImage: cgImage)
        let maskCIImage = CIImage(cvPixelBuffer: mask)

        // 使用 CoreImage 滤镜应用蒙版去背景
        guard let filter = CIFilter(name: "CIBlendWithMask") else {
            print("[SAM2Service] ❌ 创建 CIBlendWithMask 滤镜失败")
            return nil
        }
        filter.setValue(inputImage, forKey: kCIInputImageKey)
        filter.setValue(maskCIImage, forKey: kCIInputMaskImageKey)
        filter.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)

        guard let outputCIImage = filter.outputImage else {
            print("[SAM2Service] ❌ 滤镜输出为空")
            return nil
        }

        let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        guard var resultCG = context.createCGImage(
            outputCIImage,
            from: outputCIImage.extent
        ) else {
            print("[SAM2Service] ❌ createCGImage 失败")
            return nil
        }

        // 添加白色描边
        if style.enableStroke {
            if let strokedCG = addStrokeToImage(
                image: resultCG,
                mask: maskCIImage,
                strokeColor: style.strokeColor,
                strokeWidth: style.strokeWidth,
                context: context
            ) {
                resultCG = strokedCG
                print("[SAM2Service] ✅ 描边添加完成")
            }
        }

        // 裁剪透明区域
        if let croppedCG = cropToContent(image: resultCG) {
            print("[SAM2Service] ✅ 裁剪完成")
            return UIImage(cgImage: croppedCG, scale: scale, orientation: .up)
        }

        return UIImage(cgImage: resultCG, scale: scale, orientation: .up)
    }

    /// 给去背景的图片添加外部描边效果
    /// 描边在主体外围，类似贴纸效果
    /// 先扩展画布大小，然后添加描边，确保描边不被裁掉
    private func addStrokeToImage(
        image: CGImage,
        mask: CIImage,
        strokeColor: UIColor,
        strokeWidth: CGFloat,
        context: CIContext
    ) -> CGImage? {
        let originalWidth = image.width
        let originalHeight = image.height
        let originalExtent = CGRect(x: 0, y: 0, width: originalWidth, height: originalHeight)

        print("[SAM2Service] 🔴 开始添加外部描边，宽度: \(strokeWidth)")
        print("[SAM2Service] 📐 原图尺寸: \(originalWidth) x \(originalHeight)")

        // 1. 扩展画布 - 为描边留出空间
        let expandSize = Int(ceil(strokeWidth * 1.5))  // 每边扩展描边宽度的 1.5 倍
        let newWidth = originalWidth + expandSize * 2
        let newHeight = originalHeight + expandSize * 2
        let newExtent = CGRect(x: 0, y: 0, width: newWidth, height: newHeight)

        print("[SAM2Service] 📐 扩展后画布: \(newWidth) x \(newHeight)")

        // 2. 将原图绘制到扩展画布的中心
        guard let expandedContext = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            print("[SAM2Service] ❌ 创建扩展画布失败")
            return nil
        }

        // 清空画布（透明）
        expandedContext.clear(CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        // 将原图绘制到中心
        let drawRect = CGRect(x: expandSize, y: expandSize, width: originalWidth, height: originalHeight)
        expandedContext.draw(image, in: drawRect)

        guard let expandedImage = expandedContext.makeImage() else {
            print("[SAM2Service] ❌ 扩展图像失败")
            return nil
        }
        print("[SAM2Service] ✅ 画布扩展完成")

        // 3. 扩展蒙版到相同尺寸
        guard let maskContext = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            print("[SAM2Service] ❌ 创建蒙版画布失败")
            return nil
        }

        // 渲染原始蒙版到扩展画布的中心
        if let originalMaskCG = context.createCGImage(mask, from: originalExtent) {
            maskContext.draw(originalMaskCG, in: drawRect)
        }

        guard let expandedMaskCG = maskContext.makeImage() else {
            print("[SAM2Service] ❌ 扩展蒙版失败")
            return nil
        }
        let expandedMask = CIImage(cgImage: expandedMaskCG)
        print("[SAM2Service] ✅ 蒙版扩展完成")

        // 4. 扩张蒙版 - 让蒙版向外扩展描边宽度
        guard let dilateFilter = CIFilter(name: "CIMorphologyMaximum") else {
            print("[SAM2Service] ❌ 创建 CIMorphologyMaximum 失败")
            return nil
        }
        dilateFilter.setValue(expandedMask, forKey: kCIInputImageKey)
        dilateFilter.setValue(strokeWidth, forKey: kCIInputRadiusKey)

        guard let dilatedMask = dilateFilter.outputImage else {
            print("[SAM2Service] ❌ 扩张蒙版失败")
            return nil
        }
        print("[SAM2Service] ✅ 蒙版形态学扩张完成")

        // 5. 扩张蒙版 - 原始蒙版 = 外部边缘区域（描边区域）
        guard let subtractFilter = CIFilter(name: "CISubtractBlendMode") else {
            print("[SAM2Service] ❌ 创建 CISubtractBlendMode 失败")
            return nil
        }
        subtractFilter.setValue(dilatedMask, forKey: kCIInputImageKey)
        subtractFilter.setValue(expandedMask, forKey: kCIInputBackgroundImageKey)

        guard let strokeRegionMask = subtractFilter.outputImage else {
            print("[SAM2Service] ❌ 计算描边区域失败")
            return nil
        }
        print("[SAM2Service] ✅ 描边区域蒙版计算完成")

        // 6. 创建描边颜色
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        strokeColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        print("[SAM2Service] 🎨 描边颜色 RGBA: (\(r), \(g), \(b), \(a))")

        guard let strokeColorFilter = CIFilter(name: "CIConstantColorGenerator") else {
            return nil
        }
        let strokeColorVector = CIVector(x: r, y: g, z: b, w: a)
        strokeColorFilter.setValue(strokeColorVector, forKey: kCIInputColorKey)

        guard let strokeColorImage = strokeColorFilter.outputImage else {
            return nil
        }

        // 7. 使用描边区域蒙版应用颜色
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            return nil
        }
        blendFilter.setValue(strokeColorImage, forKey: kCIInputImageKey)
        blendFilter.setValue(strokeRegionMask, forKey: kCIInputMaskImageKey)

        guard let strokedLayer = blendFilter.outputImage else {
            print("[SAM2Service] ❌ 应用描边颜色失败")
            return nil
        }
        print("[SAM2Service] ✅ 描边颜色应用完成")

        // 8. 合成：描边在下层，主体在上层
        guard let compositeFilter = CIFilter(name: "CISourceOverCompositing") else {
            return nil
        }
        compositeFilter.setValue(CIImage(cgImage: expandedImage), forKey: kCIInputImageKey)
        compositeFilter.setValue(strokedLayer, forKey: kCIInputBackgroundImageKey)

        guard let outputCIImage = compositeFilter.outputImage,
              let resultCG = context.createCGImage(outputCIImage, from: newExtent) else {
            print("[SAM2Service] ❌ 最终合成失败")
            return nil
        }

        print("[SAM2Service] ✅ 外部描边完成！最终尺寸: \(resultCG.width) x \(resultCG.height)")
        return resultCG
    }

    /// 旋转180度并裁剪掉透明区域
    private func rotateAndCrop(image: CGImage, scale: CGFloat) -> UIImage? {
        let width = image.width
        let height = image.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        ) else {
            print("[SAM2Service] ❌ 创建旋转上下文失败")
            return UIImage(cgImage: image, scale: scale, orientation: .up)
        }

        // 旋转180度的变换（上下颠倒）
        context.translateBy(x: CGFloat(width), y: CGFloat(height))
        context.rotate(by: .pi)

        // 绘制旋转后的图像
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let rotatedCG = context.makeImage() else {
            print("[SAM2Service] ❌ 旋转失败")
            return UIImage(cgImage: image, scale: scale, orientation: .up)
        }

        // 检测并裁剪非透明区域
        if let croppedCG = cropToContent(image: rotatedCG) {
            print("[SAM2Service] ✅ 旋转180度并裁剪完成")
            return UIImage(cgImage: croppedCG, scale: scale, orientation: .up)
        }

        return UIImage(cgImage: rotatedCG, scale: scale, orientation: .up)
    }

    /// 裁剪图像到实际内容区域（移除透明边距）
    private func cropToContent(image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

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
            return nil
        }

        // 添加边距以保留文物边缘
        let padding: Int = 20
        minX = max(0, minX - padding)
        minY = max(0, minY - padding)
        maxX = min(width - 1, maxX + padding)
        maxY = min(height - 1, maxY + padding)

        let contentWidth = maxX - minX + 1
        let contentHeight = maxY - minY + 1

        return image.cropping(to: CGRect(x: minX, y: minY, width: contentWidth, height: contentHeight))
    }
}

// MARK: - UIImage 方向修正扩展

extension UIImage {
    /// 返回考虑了 imageOrientation 的正确方向的 UIImage
    /// 解决从相机获取的照片方向不正确的问题
    func correctlyOrientedImage() -> UIImage? {
        // 如果方向是正确的，直接返回
        if imageOrientation == .up {
            return self
        }

        // 创建 CGContext 来旋转图片
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