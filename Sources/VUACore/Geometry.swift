import Foundation

/// Platform-independent 2D geometry primitives.
///
/// The core domain layer deliberately avoids CoreGraphics so models stay
/// `Codable`, `Sendable`, and testable on any platform.

public struct VPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double = 0, y: Double = 0) {
        self.x = x
        self.y = y
    }

    public static let zero = VPoint()
}

public struct VSize: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double = 0, height: Double = 0) {
        self.width = width
        self.height = height
    }

    public static let zero = VSize()
}

public struct VRect: Codable, Hashable, Sendable {
    public var origin: VPoint
    public var size: VSize

    public init(origin: VPoint = .zero, size: VSize = .zero) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.origin = VPoint(x: x, y: y)
        self.size = VSize(width: width, height: height)
    }

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }
    public var midX: Double { origin.x + size.width / 2 }
    public var midY: Double { origin.y + size.height / 2 }
    public var width: Double { size.width }
    public var height: Double { size.height }

    public static let zero = VRect()

    public func contains(_ p: VPoint) -> Bool {
        p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
    }

    public func intersects(_ other: VRect) -> Bool {
        minX < other.maxX && maxX > other.minX &&
        minY < other.maxY && maxY > other.minY
    }

    /// Smallest rectangle enclosing both receiver and `other`.
    public func union(_ other: VRect) -> VRect {
        let nx = Swift.min(minX, other.minX)
        let ny = Swift.min(minY, other.minY)
        let mx = Swift.max(maxX, other.maxX)
        let my = Swift.max(maxY, other.maxY)
        return VRect(x: nx, y: ny, width: mx - nx, height: my - ny)
    }
}

public struct VEdgeInsets: Codable, Hashable, Sendable {
    public var top: Double
    public var leading: Double
    public var bottom: Double
    public var trailing: Double

    public init(top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public static let zero = VEdgeInsets()
}
