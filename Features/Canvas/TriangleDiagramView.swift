import SwiftUI

struct TriangleDiagramView: View {
    let spec: TriangleDiagramSpec
    let selectedSegment: String?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let padding = min(size.width, size.height) * 0.12
            let drawSize = CGSize(width: max(size.width - padding * 2, 1), height: max(size.height - padding * 2, 1))

            Canvas { context, _ in
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
                    var linePath = Path()
                    linePath.move(to: a)
                    linePath.addLine(to: b)
                    let width: CGFloat = segment == selectedSegment ? 4 : 2
                    context.stroke(linePath, with: .color(.primary), lineWidth: width)
                }

                let centroid = triangleCentroid(padding: padding, drawSize: drawSize)
                let labelInset: CGFloat = 8
                let labelOffset: CGFloat = 20
                for (key, label) in spec.vertexLabels {
                    guard let pt = point(key) else { continue }
                    let direction = normalized(CGPoint(x: pt.x - centroid.x, y: pt.y - centroid.y))
                    var labelPoint = CGPoint(
                        x: pt.x + direction.x * labelOffset,
                        y: pt.y + direction.y * labelOffset
                    )
                    labelPoint.x = min(max(labelPoint.x, padding + labelInset), size.width - padding - labelInset)
                    labelPoint.y = min(max(labelPoint.y, padding + labelInset), size.height - padding - labelInset)
                    let text = Text(label)
                        .font(.system(size: 18, weight: .bold))
                    context.draw(text, at: labelPoint)
                }

                if let vertexKey = spec.rightAngleAt,
                   let vertex = point(vertexKey) {
                    let neighbors = neighborKeys(for: vertexKey)
                    if neighbors.count >= 2,
                       let p1 = point(neighbors[0]),
                       let p2 = point(neighbors[1]) {
                        let marker = min(drawSize.width, drawSize.height) * 0.08
                        let u = normalized(CGPoint(x: p1.x - vertex.x, y: p1.y - vertex.y))
                        let v = normalized(CGPoint(x: p2.x - vertex.x, y: p2.y - vertex.y))
                        let a = CGPoint(x: vertex.x + u.x * marker, y: vertex.y + u.y * marker)
                        let b = CGPoint(x: a.x + v.x * marker, y: a.y + v.y * marker)
                        let c = CGPoint(x: vertex.x + v.x * marker, y: vertex.y + v.y * marker)

                        var markerPath = Path()
                        markerPath.move(to: a)
                        markerPath.addLine(to: b)
                        markerPath.addLine(to: c)
                        context.stroke(markerPath, with: .color(.primary), lineWidth: 2)
                    }
                }
            }
        }
    }

    private func neighborKeys(for vertexKey: String) -> [String] {
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

    private func normalized(_ vector: CGPoint) -> CGPoint {
        let length = max(sqrt(vector.x * vector.x + vector.y * vector.y), 0.0001)
        return CGPoint(x: vector.x / length, y: vector.y / length)
    }

    private func triangleCentroid(padding: CGFloat, drawSize: CGSize) -> CGPoint {
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
}
