import Foundation
import VUACore

/// Produces snap adjustments and alignment guides while dragging a layer.
public enum Snapping {
    public struct Guide: Hashable, Sendable {
        public enum Orientation: Sendable { case vertical, horizontal }
        public var orientation: Orientation
        public var position: Double
    }

    public struct Result: Sendable {
        public var frame: VRect
        public var guides: [Guide]
    }

    /// Snaps `moving` to nearby edges/centers of `others` within `threshold`.
    public static func snap(_ moving: VRect, to others: [VRect], threshold: Double = 6) -> Result {
        var frame = moving
        var guides: [Guide] = []

        let movingXs = [moving.minX, moving.midX, moving.maxX]
        let movingYs = [moving.minY, moving.midY, moving.maxY]

        var bestDX: Double? = nil
        var bestDY: Double? = nil

        for other in others {
            for ox in [other.minX, other.midX, other.maxX] {
                for mx in movingXs {
                    let d = ox - mx
                    if abs(d) <= threshold, abs(d) < abs(bestDX ?? .infinity) {
                        bestDX = d
                    }
                }
            }
            for oy in [other.minY, other.midY, other.maxY] {
                for my in movingYs {
                    let d = oy - my
                    if abs(d) <= threshold, abs(d) < abs(bestDY ?? .infinity) {
                        bestDY = d
                    }
                }
            }
        }

        if let dx = bestDX {
            frame.origin.x += dx
            guides.append(Guide(orientation: .vertical, position: frame.midX))
        }
        if let dy = bestDY {
            frame.origin.y += dy
            guides.append(Guide(orientation: .horizontal, position: frame.midY))
        }
        return Result(frame: frame, guides: guides)
    }
}
