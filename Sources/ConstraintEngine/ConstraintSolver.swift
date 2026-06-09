import Foundation
import VUACore
import LayerEngine

/// Resolves a layer's frame from its pin constraints relative to its parent's
/// content size. A lightweight, deterministic solver (not a full Cassowary
/// system) sufficient for edge pinning, centering, and proportional sizing.
public struct ConstraintSolver: Sendable {
    public init() {}

    /// Computes a layer frame within a parent of `parentSize`, applying the
    /// layer's constraints on top of its authored frame.
    public func resolveFrame(for layer: Layer, in parentSize: VSize) -> VRect {
        var frame = layer.frame
        // Sort by priority so higher-priority constraints win.
        let constraints = layer.constraints.sorted { $0.priority > $1.priority }

        var pinnedLeading: Double?
        var pinnedTrailing: Double?
        var pinnedTop: Double?
        var pinnedBottom: Double?

        for c in constraints where c.targetLayerID == nil {
            switch c.edge {
            case .leading:  pinnedLeading = c.constant
            case .trailing: pinnedTrailing = parentSize.width - c.constant
            case .top:      pinnedTop = c.constant
            case .bottom:   pinnedBottom = parentSize.height - c.constant
            case .centerX:  frame.origin.x = (parentSize.width - frame.width) / 2 + c.constant
            case .centerY:  frame.origin.y = (parentSize.height - frame.height) / 2 + c.constant
            case .width:    frame.size.width = parentSize.width * c.multiplier + c.constant
            case .height:   frame.size.height = parentSize.height * c.multiplier + c.constant
            }
        }

        // Horizontal resolution.
        if let l = pinnedLeading, let t = pinnedTrailing {
            frame.origin.x = l
            frame.size.width = max(0, t - l)
        } else if let l = pinnedLeading {
            frame.origin.x = l
        } else if let t = pinnedTrailing {
            frame.origin.x = t - frame.width
        }

        // Vertical resolution.
        if let top = pinnedTop, let bot = pinnedBottom {
            frame.origin.y = top
            frame.size.height = max(0, bot - top)
        } else if let top = pinnedTop {
            frame.origin.y = top
        } else if let bot = pinnedBottom {
            frame.origin.y = bot - frame.height
        }

        return frame
    }
}
