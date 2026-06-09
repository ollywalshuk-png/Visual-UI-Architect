import Foundation
import VUACore

/// Pure, value-semantics operations over the layer tree. Every mutation
/// returns via `inout`, leaving undo/redo and persistence to higher layers.
public enum LayerTree {

    // MARK: - Lookup

    /// Path of indices from a root to the layer with `id`, if present.
    public static func indexPath(of id: UUID, in roots: [Layer]) -> [Int]? {
        for (i, layer) in roots.enumerated() {
            if layer.id == id { return [i] }
            if let sub = indexPath(of: id, in: layer.children) {
                return [i] + sub
            }
        }
        return nil
    }

    /// Returns the absolute (canvas-space) frame of a layer by accumulating
    /// parent origins down the tree.
    public static func absoluteFrame(of id: UUID, in roots: [Layer]) -> VRect? {
        func search(_ layers: [Layer], offset: VPoint) -> VRect? {
            for layer in layers {
                let abs = VRect(
                    x: offset.x + layer.frame.origin.x,
                    y: offset.y + layer.frame.origin.y,
                    width: layer.frame.width, height: layer.frame.height)
                if layer.id == id { return abs }
                if let found = search(layer.children, offset: abs.origin) { return found }
            }
            return nil
        }
        return search(roots, offset: .zero)
    }

    // MARK: - Mutation

    /// Applies `transform` to the layer with `id` anywhere in the tree.
    /// Returns true if a matching layer was found.
    @discardableResult
    public static func update(_ id: UUID, in roots: inout [Layer], _ transform: (inout Layer) -> Void) -> Bool {
        for i in roots.indices {
            if roots[i].id == id {
                transform(&roots[i])
                return true
            }
            if update(id, in: &roots[i].children, transform) {
                return true
            }
        }
        return false
    }

    /// Removes and returns the layer with `id`.
    @discardableResult
    public static func remove(_ id: UUID, from roots: inout [Layer]) -> Layer? {
        for i in roots.indices {
            if roots[i].id == id {
                return roots.remove(at: i)
            }
            if let removed = remove(id, from: &roots[i].children) {
                return removed
            }
        }
        return nil
    }

    /// Whether a layer can move one step toward the front (later sibling index).
    public static func canReorder(_ id: UUID, towardFront: Bool, in roots: [Layer]) -> Bool {
        guard let path = indexPath(of: id, in: roots), let index = path.last else { return false }
        let siblings = siblingArray(at: path, in: roots)
        if towardFront { return index < siblings.count - 1 }
        return index > 0
    }

    /// Swaps a layer one step within its sibling list. Toward front = later index
    /// (drawn on top); toward back = earlier index.
    @discardableResult
    public static func reorder(_ id: UUID, towardFront: Bool, in roots: inout [Layer]) -> Bool {
        for i in roots.indices {
            if roots[i].id == id {
                if towardFront {
                    guard i < roots.count - 1 else { return false }
                    roots.swapAt(i, i + 1)
                } else {
                    guard i > 0 else { return false }
                    roots.swapAt(i, i - 1)
                }
                return true
            }
            if reorder(id, towardFront: towardFront, in: &roots[i].children) {
                return true
            }
        }
        return false
    }

    /// Inserts `layer` as a child of `parentID` (or at root when nil).
    public static func insert(_ layer: Layer, into roots: inout [Layer], parentID: UUID?, at index: Int? = nil) {
        guard let parentID else {
            let idx = index.map { Swift.min(Swift.max(0, $0), roots.count) } ?? roots.count
            roots.insert(layer, at: idx)
            return
        }
        update(parentID, in: &roots) { parent in
            let idx = index.map { Swift.min(Swift.max(0, $0), parent.children.count) } ?? parent.children.count
            parent.children.insert(layer, at: idx)
        }
    }

    // MARK: - Hit testing

    /// Top-most visible, unlocked layer containing `point` (canvas space).
    public static func hitTest(_ point: VPoint, in roots: [Layer]) -> UUID? {
        func search(_ layers: [Layer], offset: VPoint) -> UUID? {
            // Front-to-back: later siblings are drawn on top.
            for layer in layers.reversed() {
                guard layer.isVisible else { continue }
                let absOrigin = VPoint(x: offset.x + layer.frame.origin.x,
                                       y: offset.y + layer.frame.origin.y)
                let absRect = VRect(origin: absOrigin, size: layer.frame.size)
                if let child = search(layer.children, offset: absOrigin) {
                    return child
                }
                if !layer.isLocked && absRect.contains(point) {
                    return layer.id
                }
            }
            return nil
        }
        return search(roots, offset: .zero)
    }

    // MARK: - Private

    private static func siblingArray(at path: [Int], in roots: [Layer]) -> [Layer] {
        guard !path.isEmpty else { return [] }
        if path.count == 1 { return roots }
        var layers = roots
        for index in path.dropLast() {
            guard index < layers.count else { return [] }
            layers = layers[index].children
        }
        return layers
    }
}
