#if os(iOS)
import UIKit
import PencilKit
#endif

#if os(iOS)
struct VisionGateResult {
    let ok: Bool
    let reasons: [String]
}

struct VisionRequestConfig {
    var enableCropping: Bool = true
    var maxLatencyMode: MaxLatencyMode = .normal
    var longEdge: CGFloat = 1200
    var paddingPct: CGFloat = 0.08
    var minCropSize: CGSize = CGSize(width: 512, height: 512)
    var minKeepAreaFraction: CGFloat = 0.6
    var maxInkCoverageFraction: CGFloat = 0.35
    var minInkAreaFraction: CGFloat = 0.002
    var minInkBoundsSize: CGFloat = 8
    var maxPNGBytes: Int = 1_800_000
    var jpegFallbackQuality: CGFloat = 0.85
}

enum MaxLatencyMode {
    case normal
    case aggressive
}

struct VisionResult: Codable {
    let detectedSegment: String?
    let ambiguityScore: Double
    let confidence: Double
    let reasonCodes: [String]
    let studentFeedback: String
}

struct VisionPipeline {
    @MainActor
    static func renderSubmissionImage(canvasView: PKCanvasView, background: UIImage?) -> UIImage {
        let size = canvasView.bounds.size
        let scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: size, format: rendererFormat(scale: scale))
        return renderer.image { context in
            fillWhite(context.cgContext, size: size)
            if let background {
                background.draw(in: CGRect(origin: .zero, size: size))
            }
            let ink = canvasView.drawing.image(from: canvasView.bounds, scale: scale)
            ink.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    @MainActor
    static func flattenOnWhite(_ image: UIImage) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size, format: rendererFormat(scale: image.scale))
        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: image.size))
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    @MainActor
    static func cropToContentBounds(
        _ image: UIImage,
        paddingPct: CGFloat = 0.08,
        minSize: CGSize = CGSize(width: 512, height: 512),
        inkDrawing: PKDrawing? = nil,
        canvasSize: CGSize? = nil,
        minKeepAreaFraction: CGFloat = 0.6
    ) -> UIImage {
        let imageSize = image.size
        let originalRect = CGRect(origin: .zero, size: imageSize)

        var cropRect: CGRect?
        if let inkDrawing, let canvasSize {
            cropRect = inkBoundsInImage(inkDrawing: inkDrawing, canvasSize: canvasSize, imageSize: imageSize)
        } else {
            cropRect = nonWhiteBounds(image)
        }

        guard var rect = cropRect, !rect.isEmpty else { return image }

        let padX = rect.width * paddingPct
        let padY = rect.height * paddingPct
        rect = rect.insetBy(dx: -padX, dy: -padY)
        rect = rect.intersection(originalRect)

        let cropArea = rect.width * rect.height
        let originalArea = imageSize.width * imageSize.height
        if cropArea / max(originalArea, 1) < minKeepAreaFraction {
            return image
        }

        if rect.width < minSize.width || rect.height < minSize.height {
            return image
        }

        guard let cgImage = image.cgImage,
              let cropped = cgImage.cropping(to: rect.integral) else {
            return image
        }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    @MainActor
    static func resizeForVision(_ image: UIImage, longEdge: CGFloat = 1200) -> UIImage {
        let size = image.size
        let maxEdge = max(size.width, size.height)
        guard maxEdge > longEdge else { return image }
        let scale = longEdge / maxEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize, format: rendererFormat(scale: image.scale))
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    @MainActor
    static func encodeForAPIPayload(_ image: UIImage, maxPNGBytes: Int = 1_800_000, jpegQuality: CGFloat = 0.85) -> (mime: String, base64: String, byteCount: Int)? {
        if let png = image.pngData(), png.count <= maxPNGBytes {
            return ("image/png", png.base64EncodedString(), png.count)
        }
        if let jpeg = image.jpegData(compressionQuality: jpegQuality) {
            return ("image/jpeg", jpeg.base64EncodedString(), jpeg.count)
        }
        return nil
    }

    static func shouldCallVision(inkDrawing: PKDrawing?, renderedImage: UIImage) -> VisionGateResult {
        var reasons: [String] = []
        if let inkDrawing {
            let bounds = inkDrawing.bounds
            let strokesCount = inkDrawing.strokes.count
            if strokesCount == 0 || bounds.isEmpty {
                return VisionGateResult(ok: false, reasons: ["NO_INK"])
            }

            let inkArea = bounds.width * bounds.height
            let imageArea = renderedImage.size.width * renderedImage.size.height
            if inkArea / max(imageArea, 1) < 0.002 {
                return VisionGateResult(ok: false, reasons: ["TINY_MARKS"])
            }

            if inkArea / max(imageArea, 1) > 0.35 {
                reasons.append("INK_TOO_MESSY")
            }
        } else {
            let inkPixelRatio = estimateInkPixelRatio(renderedImage)
            if inkPixelRatio < 0.002 {
                return VisionGateResult(ok: false, reasons: ["NO_INK"])
            }
            if inkPixelRatio > 0.35 {
                reasons.append("INK_TOO_MESSY")
            }
        }

        return VisionGateResult(ok: true, reasons: reasons)
    }

    static func prepareAndSubmitVisionRequest(
        canvasView: PKCanvasView,
        background: UIImage?,
        prompt: String,
        config: VisionRequestConfig = VisionRequestConfig(),
        submit: @escaping (String, String) async -> VisionResult?
    ) async -> VisionResult {
        let submission = renderSubmissionImage(canvasView: canvasView, background: background)
        let flattened = flattenOnWhite(submission)

        let gate = shouldCallVision(inkDrawing: canvasView.drawing, renderedImage: flattened)
        if !gate.ok {
            return VisionResult(
                detectedSegment: nil,
                ambiguityScore: 1.0,
                confidence: 0.0,
                reasonCodes: gate.reasons,
                studentFeedback: "I can’t see a clear mark yet. Try circling or marking more clearly."
            )
        }

        var imageForVision = flattened
        if config.enableCropping {
            imageForVision = cropToContentBounds(
                imageForVision,
                paddingPct: config.paddingPct,
                minSize: config.minCropSize,
                inkDrawing: canvasView.drawing,
                canvasSize: canvasView.bounds.size,
                minKeepAreaFraction: config.minKeepAreaFraction
            )
        }

        imageForVision = resizeForVision(imageForVision, longEdge: config.longEdge)
        guard let encoded = encodeForAPIPayload(imageForVision, maxPNGBytes: config.maxPNGBytes, jpegQuality: config.jpegFallbackQuality) else {
            return VisionResult(
                detectedSegment: nil,
                ambiguityScore: 1.0,
                confidence: 0.0,
                reasonCodes: ["OTHER"],
                studentFeedback: "Something went wrong preparing your image."
            )
        }

        if let result = await submit(encoded.mime, encoded.base64) {
            return result
        }

        return VisionResult(
            detectedSegment: nil,
            ambiguityScore: 1.0,
            confidence: 0.0,
            reasonCodes: ["OTHER"],
            studentFeedback: "(AI check failed) Please try again."
        )
    }

    // MARK: - Helpers

    private static func rendererFormat(scale: CGFloat) -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return format
    }

    private static func fillWhite(_ context: CGContext, size: CGSize) {
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
    }

    private static func inkBoundsInImage(inkDrawing: PKDrawing, canvasSize: CGSize, imageSize: CGSize) -> CGRect {
        let bounds = inkDrawing.bounds
        if bounds.isEmpty || canvasSize.width == 0 || canvasSize.height == 0 {
            return .zero
        }
        let scaleX = imageSize.width / canvasSize.width
        let scaleY = imageSize.height / canvasSize.height
        return CGRect(
            x: bounds.origin.x * scaleX,
            y: bounds.origin.y * scaleY,
            width: bounds.size.width * scaleX,
            height: bounds.size.height * scaleY
        )
    }

    private static func nonWhiteBounds(_ image: UIImage) -> CGRect? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let totalBytes = bytesPerRow * height
        var pixelData = [UInt8](repeating: 0, count: totalBytes)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * bytesPerRow) + (x * bytesPerPixel)
                let r = pixelData[index]
                let g = pixelData[index + 1]
                let b = pixelData[index + 2]
                let a = pixelData[index + 3]
                if a < 10 { continue }
                let isWhite = r > 240 && g > 240 && b > 240
                if !isWhite {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        if minX > maxX || minY > maxY {
            return nil
        }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private static func estimateInkPixelRatio(_ image: UIImage) -> CGFloat {
        guard let cgImage = image.cgImage else { return 0 }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let totalBytes = bytesPerRow * height
        var pixelData = [UInt8](repeating: 0, count: totalBytes)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var inkCount = 0
        let total = width * height
        for i in stride(from: 0, to: totalBytes, by: bytesPerPixel) {
            let r = pixelData[i]
            let g = pixelData[i + 1]
            let b = pixelData[i + 2]
            let a = pixelData[i + 3]
            if a < 10 { continue }
            let isWhite = r > 240 && g > 240 && b > 240
            if !isWhite {
                inkCount += 1
            }
        }
        return CGFloat(inkCount) / CGFloat(max(total, 1))
    }
}
#else
import Foundation
import CoreGraphics
struct VisionGateResult {
    let ok: Bool
    let reasons: [String]
}

struct VisionRequestConfig {
    var enableCropping: Bool = false
    var maxLatencyMode: MaxLatencyMode = .normal
    var longEdge: Double = 1200
    var paddingPct: Double = 0.08
    var minCropSize: CGSize = CGSize(width: 512, height: 512)
    var minKeepAreaFraction: Double = 0.6
    var maxInkCoverageFraction: Double = 0.35
    var minInkAreaFraction: Double = 0.002
    var minInkBoundsSize: Double = 8
    var maxPNGBytes: Int = 1_800_000
    var jpegFallbackQuality: Double = 0.85
}

enum MaxLatencyMode {
    case normal
    case aggressive
}

struct VisionResult: Codable {
    let detectedSegment: String?
    let ambiguityScore: Double
    let confidence: Double
    let reasonCodes: [String]
    let studentFeedback: String
}

struct VisionPipeline {
    static func renderSubmissionImage(canvasView: AnyObject, background: AnyObject?) -> AnyObject { canvasView }
    static func flattenOnWhite(_ image: AnyObject) -> AnyObject { image }
    static func cropToContentBounds(_ image: AnyObject, paddingPct: CGFloat = 0.08, minSize: CGSize = CGSize(width: 512, height: 512), inkDrawing: AnyObject? = nil, canvasSize: CGSize? = nil, minKeepAreaFraction: CGFloat = 0.6) -> AnyObject { image }
    static func resizeForVision(_ image: AnyObject, longEdge: CGFloat = 1200) -> AnyObject { image }
    static func encodeForAPIPayload(_ image: AnyObject, maxPNGBytes: Int = 1_800_000, jpegQuality: CGFloat = 0.85) -> (mime: String, base64: String, byteCount: Int)? { nil }
    static func shouldCallVision(inkDrawing: AnyObject?, renderedImage: AnyObject) -> VisionGateResult { VisionGateResult(ok: false, reasons: ["UNSUPPORTED_PLATFORM"]) }
    static func prepareAndSubmitVisionRequest(canvasView: AnyObject, background: AnyObject?, prompt: String, config: VisionRequestConfig = VisionRequestConfig(), submit: @escaping (String, String) async -> VisionResult?) async -> VisionResult {
        VisionResult(detectedSegment: nil, ambiguityScore: 1.0, confidence: 0.0, reasonCodes: ["UNSUPPORTED_PLATFORM"], studentFeedback: "Vision is not supported on this platform.")
    }
}
#endif
