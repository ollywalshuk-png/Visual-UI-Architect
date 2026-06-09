import Foundation
import VUACore
import LayerEngine

/// Size classes used to drive adaptive layout decisions and breakpoints.
public enum SizeClass: String, Sendable, CaseIterable {
    case compact   // phones, narrow windows
    case regular   // tablets, standard windows
    case large     // desktops, wide windows

    public static func classify(width: Double) -> SizeClass {
        switch width {
        case ..<500: return .compact
        case ..<900: return .regular
        default: return .large
        }
    }
}

/// A breakpoint describing overrides applied at or above a width threshold.
public struct Breakpoint: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var minWidth: Double
    public var sizeClass: SizeClass

    public init(id: UUID = UUID(), minWidth: Double, sizeClass: SizeClass) {
        self.id = id
        self.minWidth = minWidth
        self.sizeClass = sizeClass
    }

    public static let defaults: [Breakpoint] = [
        Breakpoint(minWidth: 0, sizeClass: .compact),
        Breakpoint(minWidth: 500, sizeClass: .regular),
        Breakpoint(minWidth: 900, sizeClass: .large)
    ]
}

/// Produces an adapted layer tree for a target canvas size by proportionally
/// reflowing root frames. Containers scale their children proportionally.
public struct ResponsiveEngine: Sendable {
    public init() {}

    /// Scales `roots` authored at `from` size to fit `to` size, preserving
    /// relative positions and proportions (a sensible automatic adaptation).
    public func adapt(_ roots: [Layer], from: VSize, to: VSize) -> [Layer] {
        guard from.width > 0, from.height > 0 else { return roots }
        let sx = to.width / from.width
        let sy = to.height / from.height
        return roots.map { scale($0, sx: sx, sy: sy) }
    }

    private func scale(_ layer: Layer, sx: Double, sy: Double) -> Layer {
        var copy = layer
        copy.frame = VRect(
            x: layer.frame.origin.x * sx,
            y: layer.frame.origin.y * sy,
            width: layer.frame.width * sx,
            height: layer.frame.height * sy)
        // Children frames are parent-relative; scale them by the same factors.
        copy.children = layer.children.map { scale($0, sx: sx, sy: sy) }
        return copy
    }
}
