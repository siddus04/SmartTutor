import XCTest
import UIKit
import PencilKit

final class VisionPipelineTests: XCTestCase {
    func testFlattenOnWhiteOpaque() {
        let image = makeTransparentImage(size: CGSize(width: 64, height: 64))
        let flattened = VisionPipeline.flattenOnWhite(image)
        let pixel = samplePixel(flattened, at: CGPoint(x: 1, y: 1))
        XCTAssertEqual(pixel.a, 255)
        XCTAssertGreaterThan(pixel.r, 240)
        XCTAssertGreaterThan(pixel.g, 240)
        XCTAssertGreaterThan(pixel.b, 240)
    }

    func testNoInkGateBlocks() {
        let drawing = PKDrawing()
        let image = makeWhiteImage(size: CGSize(width: 256, height: 256))
        let gate = VisionPipeline.shouldCallVision(inkDrawing: drawing, renderedImage: image)
        XCTAssertFalse(gate.ok)
        XCTAssertTrue(gate.reasons.contains("NO_INK"))
    }

    func testCropMinSizeFallback() {
        let image = makeWhiteImage(size: CGSize(width: 800, height: 800), dotAt: CGPoint(x: 400, y: 400))
        let cropped = VisionPipeline.cropToContentBounds(image, minSize: CGSize(width: 512, height: 512))
        XCTAssertEqual(cropped.size.width, 800, accuracy: 1)
        XCTAssertEqual(cropped.size.height, 800, accuracy: 1)
    }
}

private func makeTransparentImage(size: CGSize) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: size, format: {
        let f = UIGraphicsImageRendererFormat()
        f.opaque = false
        return f
    }())
    return renderer.image { _ in
        UIColor.clear.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
    }
}

private func makeWhiteImage(size: CGSize, dotAt: CGPoint? = nil) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: size, format: {
        let f = UIGraphicsImageRendererFormat()
        f.opaque = true
        return f
    }())
    return renderer.image { _ in
        UIColor.white.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        if let dotAt {
            UIColor.black.setFill()
            UIRectFill(CGRect(x: dotAt.x, y: dotAt.y, width: 2, height: 2))
        }
    }
}

private func samplePixel(_ image: UIImage, at point: CGPoint) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
    guard let cgImage = image.cgImage else { return (0, 0, 0, 0) }
    let width = cgImage.width
    let height = cgImage.height
    let x = min(max(Int(point.x), 0), width - 1)
    let y = min(max(Int(point.y), 0), height - 1)
    let bytesPerPixel = 4
    var pixelData = [UInt8](repeating: 0, count: bytesPerPixel)
    guard let context = CGContext(
        data: &pixelData,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerPixel,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return (0, 0, 0, 0)
    }
    context.translateBy(x: CGFloat(-x), y: CGFloat(y - height + 1))
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (pixelData[0], pixelData[1], pixelData[2], pixelData[3])
}
