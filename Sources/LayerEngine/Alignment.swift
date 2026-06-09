import Foundation
import VUACore

/// Align & distribute operations over a set of sibling layers, expressed as
/// frame edits. Operates on frames in a shared coordinate space.
public enum Alignment {
    public enum Edge { case left, hCenter, right, top, vCenter, bottom }
    public enum Axis { case horizontal, vertical }

    /// Returns new frames keyed by id after aligning to `edge`.
    public static func align(_ frames: [UUID: VRect], to edge: Edge) -> [UUID: VRect] {
        guard !frames.isEmpty else { return frames }
        let rects = Array(frames.values)
        var result = frames
        switch edge {
        case .left:
            let m = rects.map(\.minX).min()!
            for (k, _) in frames { result[k]?.origin.x = m }
        case .right:
            let m = rects.map(\.maxX).max()!
            for (k, r) in frames { result[k]?.origin.x = m - r.width }
        case .hCenter:
            let c = rects.map(\.midX).reduce(0, +) / Double(rects.count)
            for (k, r) in frames { result[k]?.origin.x = c - r.width / 2 }
        case .top:
            let mTop = rects.map(\.minY).min()!
            for (k, _) in frames { result[k]?.origin.y = mTop }
        case .bottom:
            let m = rects.map(\.maxY).max()!
            for (k, r) in frames { result[k]?.origin.y = m - r.height }
        case .vCenter:
            let c = rects.map(\.midY).reduce(0, +) / Double(rects.count)
            for (k, r) in frames { result[k]?.origin.y = c - r.height / 2 }
        }
        return result
    }

    /// Distributes layers so spacing between them is equal along `axis`.
    public static func distribute(_ frames: [UUID: VRect], along axis: Axis) -> [UUID: VRect] {
        guard frames.count > 2 else { return frames }
        var result = frames
        switch axis {
        case .horizontal:
            let sorted = frames.sorted { $0.value.midX < $1.value.midX }
            let first = sorted.first!.value, last = sorted.last!.value
            let totalWidth = sorted.reduce(0.0) { $0 + $1.value.width }
            let span = last.maxX - first.minX
            let gap = (span - totalWidth) / Double(sorted.count - 1)
            var x = first.minX
            for (k, r) in sorted {
                result[k]?.origin.x = x
                x += r.width + gap
            }
        case .vertical:
            let sorted = frames.sorted { $0.value.midY < $1.value.midY }
            let first = sorted.first!.value, last = sorted.last!.value
            let totalHeight = sorted.reduce(0.0) { $0 + $1.value.height }
            let span = last.maxY - first.minY
            let gap = (span - totalHeight) / Double(sorted.count - 1)
            var y = first.minY
            for (k, r) in sorted {
                result[k]?.origin.y = y
                y += r.height + gap
            }
        }
        return result
    }
}
