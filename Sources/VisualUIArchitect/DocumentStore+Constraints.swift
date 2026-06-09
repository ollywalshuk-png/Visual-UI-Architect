import Foundation
import VUACore
import LayerEngine
import ConstraintEngine

/// Visual constraint editing on the document store. Pins are authored from the
/// layer's current frame (WYSIWYG); `resolveSelectedConstraints` re-lays the
/// layer for the current parent size via the `ConstraintSolver`.
extension DocumentStore {

    /// The content size a layer is laid out within (canvas for roots, else the
    /// parent layer's size).
    func parentSize(of layerID: UUID) -> VSize {
        guard let path = LayerTree.indexPath(of: layerID, in: document.roots), path.count > 1 else {
            return document.canvasSize
        }
        // Walk to the parent layer.
        var layers = document.roots
        var parent: Layer?
        for idx in path.dropLast() {
            guard idx < layers.count else { break }
            parent = layers[idx]
            layers = layers[idx].children
        }
        return parent?.frame.size ?? document.canvasSize
    }

    func isPinned(_ edge: LayerEdge) -> Bool {
        canSelectSingle?.constraints.contains { $0.edge == edge && $0.targetLayerID == nil } ?? false
    }

    /// Adds or removes a parent-relative constraint for `edge`, computing its
    /// constant from the layer's current frame so the layout doesn't jump.
    func togglePin(_ edge: LayerEdge) {
        guard let layer = canSelectSingle else { return }
        let size = parentSize(of: layer.id)
        if isPinned(edge) {
            mutate { LayerTree.update(layer.id, in: &$0.roots) { l in
                l.constraints.removeAll { $0.edge == edge && $0.targetLayerID == nil }
            } }
            return
        }
        let constant: Double
        let multiplier: Double
        switch edge {
        case .leading:  constant = layer.frame.minX; multiplier = 1
        case .trailing: constant = size.width - layer.frame.maxX; multiplier = 1
        case .top:      constant = layer.frame.minY; multiplier = 1
        case .bottom:   constant = size.height - layer.frame.maxY; multiplier = 1
        case .centerX:  constant = layer.frame.midX - size.width / 2; multiplier = 1
        case .centerY:  constant = layer.frame.midY - size.height / 2; multiplier = 1
        case .width:    constant = layer.frame.width; multiplier = 0   // fixed absolute width
        case .height:   constant = layer.frame.height; multiplier = 0  // fixed absolute height
        }
        mutate { LayerTree.update(layer.id, in: &$0.roots) { l in
            l.constraints.removeAll { $0.edge == edge && $0.targetLayerID == nil }
            l.constraints.append(LayerConstraint(edge: edge, constant: constant, multiplier: multiplier))
        } }
    }

    func clearConstraints() {
        guard let id = selection.first else { return }
        mutate { LayerTree.update(id, in: &$0.roots) { $0.constraints.removeAll() } }
    }

    /// Re-solves the selected layer's frame from its constraints (demonstrates
    /// adaptive behaviour, e.g. after a device/orientation change).
    func resolveSelectedConstraints() {
        guard let layer = canSelectSingle, !layer.constraints.isEmpty else { return }
        let size = parentSize(of: layer.id)
        let resolved = ConstraintSolver().resolveFrame(for: layer, in: size)
        mutate { LayerTree.update(layer.id, in: &$0.roots) { $0.frame = resolved } }
    }
}
