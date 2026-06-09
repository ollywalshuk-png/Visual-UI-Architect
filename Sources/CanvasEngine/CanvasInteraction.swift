import Foundation
import VUACore
import LayerEngine

/// Resize handles on a selection bounding box.
public enum ResizeHandle: Sendable, CaseIterable {
    case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight
}

/// Pure geometry helpers backing canvas interaction (drag/resize/marquee).
/// State ownership and undo live in the app's view model; this stays testable.
public enum CanvasInteraction {

    /// Applies a translation to a frame.
    public static func translate(_ frame: VRect, by delta: VPoint) -> VRect {
        VRect(x: frame.origin.x + delta.x, y: frame.origin.y + delta.y,
              width: frame.width, height: frame.height)
    }

    /// Resizes a frame by dragging `handle` by `delta`, keeping a minimum size.
    public static func resize(_ frame: VRect, handle: ResizeHandle, by delta: VPoint, minSize: Double = 8) -> VRect {
        var minX = frame.minX, minY = frame.minY, maxX = frame.maxX, maxY = frame.maxY
        switch handle {
        case .topLeft:     minX += delta.x; minY += delta.y
        case .top:         minY += delta.y
        case .topRight:    maxX += delta.x; minY += delta.y
        case .left:        minX += delta.x
        case .right:       maxX += delta.x
        case .bottomLeft:  minX += delta.x; maxY += delta.y
        case .bottom:      maxY += delta.y
        case .bottomRight: maxX += delta.x; maxY += delta.y
        }
        if maxX - minX < minSize { maxX = minX + minSize }
        if maxY - minY < minSize { maxY = minY + minSize }
        return VRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Nudge distance for arrow-key movement (1pt, or 10pt with shift).
    public static func nudge(_ frame: VRect, dx: Double, dy: Double) -> VRect {
        VRect(x: frame.origin.x + dx, y: frame.origin.y + dy, width: frame.width, height: frame.height)
    }

    /// Layer ids whose absolute frames intersect a marquee selection rect.
    public static func marqueeSelection(_ rect: VRect, nodes: [(id: UUID, frame: VRect)]) -> Set<UUID> {
        Set(nodes.filter { rect.intersects($0.frame) }.map(\.id))
    }

    /// Bounding box enclosing a set of frames.
    public static func boundingBox(of frames: [VRect]) -> VRect? {
        guard var box = frames.first else { return nil }
        for f in frames.dropFirst() { box = box.union(f) }
        return box
    }
}
