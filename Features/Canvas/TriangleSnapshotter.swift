#if os(iOS)
import UIKit
import PencilKit

struct TriangleSnapshotter {
    struct Snapshots {
        let basePNG: Data
        let inkPNG: Data
        let combinedPNG: Data
    }

    static func makeSnapshots(canvasView: PKCanvasView, diagramSpec: TriangleDiagramSpec) -> Snapshots? {
        let bounds = canvasView.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }

        let inkImage = canvasView.drawing.image(from: bounds, scale: 2.0)
        guard let inkPNG = inkImage.pngData() else { return nil }

        let baseImage = renderBaseImage(spec: diagramSpec, size: bounds.size, scale: 2.0)
        guard let basePNG = baseImage.pngData() else { return nil }

        let combinedImage = renderCombinedImage(baseImage: baseImage, inkImage: inkImage, size: bounds.size, scale: 2.0)
        guard let combinedPNG = combinedImage.pngData() else { return nil }

        return Snapshots(basePNG: basePNG, inkPNG: inkPNG, combinedPNG: combinedPNG)
    }

    static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        return formatter.string(from: Date())
    }

    static func savePNG(data: Data, filename: String) {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = directory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            print("[AICheck] Saved \(filename) to \(url.path)")
        } catch {
            print("[AICheck] Failed to save \(filename): \(error)")
        }
    }

    private static func renderBaseImage(spec: TriangleDiagramSpec, size: CGSize, scale: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size, format: rendererFormat(scale: scale))
        return renderer.image { context in
            drawTriangle(spec: spec, in: context.cgContext, size: size)
        }
    }

    private static func renderCombinedImage(baseImage: UIImage, inkImage: UIImage, size: CGSize, scale: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size, format: rendererFormat(scale: scale))
        return renderer.image { _ in
            baseImage.draw(in: CGRect(origin: .zero, size: size))
            inkImage.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func rendererFormat(scale: CGFloat) -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return format
    }

    private static func drawTriangle(spec: TriangleDiagramSpec, in context: CGContext, size: CGSize) {
        context.saveGState()
        context.setStrokeColor(UIColor.label.cgColor)
        context.setLineWidth(2)

        let padding = min(size.width, size.height) * 0.12
        let drawSize = CGSize(width: max(size.width - padding * 2, 1), height: max(size.height - padding * 2, 1))

        func point(_ key: String) -> CGPoint? {
            guard let p = spec.points[key] else { return nil }
            return CGPoint(
                x: padding + CGFloat(p.x) * drawSize.width,
                y: padding + CGFloat(p.y) * drawSize.height
            )
        }

        for segment in spec.segments {
            let chars = Array(segment)
            guard chars.count == 2 else { continue }
            let aKey = String(chars[0])
            let bKey = String(chars[1])
            guard let a = point(aKey), let b = point(bKey) else { continue }
            context.beginPath()
            context.move(to: a)
            context.addLine(to: b)
            context.strokePath()
        }

        for (key, label) in spec.vertexLabels {
            guard let pt = point(key) else { continue }
            let centroid = triangleCentroid(spec: spec, padding: padding, drawSize: drawSize)
            let direction = normalized(CGPoint(x: pt.x - centroid.x, y: pt.y - centroid.y))
            let labelPoint = CGPoint(x: pt.x + direction.x * 20, y: pt.y + direction.y * 20)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: UIColor.label
            ]
            let text = NSAttributedString(string: label, attributes: attributes)
            text.draw(at: CGPoint(x: labelPoint.x - 6, y: labelPoint.y - 9))
        }

        if let rightKey = spec.rightAngleAt,
           let vertex = point(rightKey) {
            let neighbors = neighborKeys(spec: spec, for: rightKey)
            if neighbors.count >= 2,
               let p1 = point(neighbors[0]),
               let p2 = point(neighbors[1]) {
                let marker = min(drawSize.width, drawSize.height) * 0.08
                let u = normalized(CGPoint(x: p1.x - vertex.x, y: p1.y - vertex.y))
                let v = normalized(CGPoint(x: p2.x - vertex.x, y: p2.y - vertex.y))
                let a = CGPoint(x: vertex.x + u.x * marker, y: vertex.y + u.y * marker)
                let b = CGPoint(x: a.x + v.x * marker, y: a.y + v.y * marker)
                let c = CGPoint(x: vertex.x + v.x * marker, y: vertex.y + v.y * marker)
                context.beginPath()
                context.move(to: a)
                context.addLine(to: b)
                context.addLine(to: c)
                context.strokePath()
            }
        }

        context.restoreGState()
    }

    private static func triangleCentroid(spec: TriangleDiagramSpec, padding: CGFloat, drawSize: CGSize) -> CGPoint {
        let keys = ["A", "B", "C"]
        let points = keys.compactMap { spec.points[$0] }
        let source = points.isEmpty ? Array(spec.points.values) : points
        let count = CGFloat(max(source.count, 1))
        let sum = source.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + CGFloat(point.x), y: partial.y + CGFloat(point.y))
        }
        let avg = CGPoint(x: sum.x / count, y: sum.y / count)
        return CGPoint(
            x: padding + avg.x * drawSize.width,
            y: padding + avg.y * drawSize.height
        )
    }

    private static func neighborKeys(spec: TriangleDiagramSpec, for vertexKey: String) -> [String] {
        var neighbors: [String] = []
        for segment in spec.segments {
            let chars = Array(segment)
            guard chars.count == 2 else { continue }
            let a = String(chars[0])
            let b = String(chars[1])
            if a == vertexKey {
                neighbors.append(b)
            } else if b == vertexKey {
                neighbors.append(a)
            }
        }
        if neighbors.count >= 2 {
            return neighbors
        }
        let fallback = spec.points.keys.filter { $0 != vertexKey }
        return neighbors + fallback
    }

    private static func normalized(_ vector: CGPoint) -> CGPoint {
        let length = max(sqrt(vector.x * vector.x + vector.y * vector.y), 0.0001)
        return CGPoint(x: vector.x / length, y: vector.y / length)
    }
}
#else
import Foundation

struct TriangleSnapshotter {
    struct Snapshots {
        let basePNG: Data
        let inkPNG: Data
        let combinedPNG: Data
    }

    static func makeSnapshots(canvasView: AnyObject, diagramSpec: TriangleDiagramSpec) -> Snapshots? { nil }
    static func timestampString() -> String { "" }
    static func savePNG(data: Data, filename: String) {}
}
#endif
