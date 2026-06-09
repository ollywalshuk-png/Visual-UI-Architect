import Foundation
import VUACore

/// Snap-to-grid math. Pure so it can be unit-tested without any UI.
public enum CanvasGrid {
    /// Rounds a value to the nearest multiple of `spacing` (spacing <= 0 = no-op).
    public static func snap(_ value: Double, spacing: Double) -> Double {
        guard spacing > 0 else { return value }
        return (value / spacing).rounded() * spacing
    }

    public static func snap(_ point: VPoint, spacing: Double) -> VPoint {
        VPoint(x: snap(point.x, spacing: spacing), y: snap(point.y, spacing: spacing))
    }

    /// Snaps a frame's origin to the grid, preserving its size.
    public static func snap(_ rect: VRect, spacing: Double) -> VRect {
        VRect(origin: snap(rect.origin, spacing: spacing), size: rect.size)
    }
}

/// Zoom/fit math for the canvas viewport.
public enum CanvasViewport {
    public static let minZoom = 0.1
    public static let maxZoom = 8.0

    public static func clampZoom(_ z: Double) -> Double {
        Swift.min(maxZoom, Swift.max(minZoom, z))
    }

    /// Largest zoom that fits `content` inside `viewport` with `padding` on all
    /// sides. Returns 1.0 for empty content/viewport.
    public static func fitZoom(content: VSize, viewport: VSize, padding: Double = 40) -> Double {
        guard content.width > 0, content.height > 0,
              viewport.width > 0, viewport.height > 0 else { return 1 }
        let availW = Swift.max(1, viewport.width - padding * 2)
        let availH = Swift.max(1, viewport.height - padding * 2)
        return clampZoom(Swift.min(availW / content.width, availH / content.height))
    }

    /// Zoom that frames a selection's bounding box within the viewport.
    public static func zoomToFit(_ bounds: VRect, viewport: VSize, padding: Double = 80) -> Double {
        fitZoom(content: bounds.size, viewport: viewport, padding: padding)
    }
}

/// Ruler tick generation. Chooses a "nice" step so ticks never crowd.
public enum CanvasRuler {
    /// Returns tick positions in canvas points covering `0...lengthPoints`,
    /// spaced so adjacent ticks are at least `minPixelGap` apart on screen.
    public static func ticks(lengthPoints: Double, zoom: Double, minPixelGap: Double = 60) -> [Double] {
        guard lengthPoints > 0, zoom > 0 else { return [] }
        let minPointGap = minPixelGap / zoom
        let step = niceStep(atLeast: minPointGap)
        var positions: [Double] = []
        var v = 0.0
        while v <= lengthPoints + 0.5 {
            positions.append(v)
            v += step
        }
        return positions
    }

    /// Smallest 1/2/5 × 10ⁿ value that is ≥ `minimum`.
    public static func niceStep(atLeast minimum: Double) -> Double {
        guard minimum > 0 else { return 10 }
        let exponent = floor(log10(minimum))
        let base = pow(10, exponent)
        for m in [1.0, 2.0, 5.0, 10.0] {
            if base * m >= minimum { return base * m }
        }
        return base * 10
    }
}

/// Alignment / equal-spacing guide detection while dragging a layer.
public enum AlignmentGuides {
    public struct Result: Sendable {
        /// X positions (canvas space) of vertical alignment guides.
        public var verticals: [Double]
        /// Y positions of horizontal alignment guides.
        public var horizontals: [Double]
        public var snappedDelta: VPoint
    }

    /// Given a moving rect and sibling rects, returns alignment guides and the
    /// delta needed to snap edges/centers within `threshold`.
    public static func detect(moving: VRect, siblings: [VRect], threshold: Double = 6) -> Result {
        let movingXs = [moving.minX, moving.midX, moving.maxX]
        let movingYs = [moving.minY, moving.midY, moving.maxY]
        var bestDX: Double?
        var bestDY: Double?
        var verticals: [Double] = []
        var horizontals: [Double] = []

        for other in siblings {
            for ox in [other.minX, other.midX, other.maxX] {
                for mx in movingXs where abs(ox - mx) <= threshold {
                    let d = ox - mx
                    if abs(d) < abs(bestDX ?? .infinity) { bestDX = d }
                    verticals.append(ox)
                }
            }
            for oy in [other.minY, other.midY, other.maxY] {
                for my in movingYs where abs(oy - my) <= threshold {
                    let d = oy - my
                    if abs(d) < abs(bestDY ?? .infinity) { bestDY = d }
                    horizontals.append(oy)
                }
            }
        }
        return Result(
            verticals: Array(Set(verticals)).sorted(),
            horizontals: Array(Set(horizontals)).sorted(),
            snappedDelta: VPoint(x: bestDX ?? 0, y: bestDY ?? 0))
    }
}
