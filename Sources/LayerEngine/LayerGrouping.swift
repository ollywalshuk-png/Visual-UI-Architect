import Foundation
import VUACore

/// Phase 7 tree operations: cloning (paste), grouping, and absolute z-order.
public extension LayerTree {

    // MARK: - Cloning (copy / paste / duplicate)

    /// Deep-copies a layer, assigning fresh ids throughout. All other fields —
    /// including Phase 7 attributes (role, notes, tags, line, polygon, mask,
    /// clipShape) — are preserved. Bindings are dropped so a paste doesn't
    /// alias another layer's source anchor.
    static func cloneWithNewIDs(_ layer: Layer) -> Layer {
        Layer(
            id: UUID(),
            name: layer.name,
            kind: layer.kind,
            frame: layer.frame,
            style: layer.style,
            text: layer.text,
            assetID: layer.assetID,
            isVisible: layer.isVisible,
            isLocked: layer.isLocked,
            labelColor: layer.labelColor,
            constraints: layer.constraints,
            binding: nil,   // drop source anchor so a paste doesn't alias.
            control: layer.control,
            role: layer.role,
            notes: layer.notes,
            tags: layer.tags,
            isCollapsed: layer.isCollapsed,
            isAccessibilityHidden: layer.isAccessibilityHidden,
            line: layer.line,
            polygon: layer.polygon,
            mask: layer.mask,
            clipShape: layer.clipShape,
            componentID: layer.componentID,   // duplicating an instance keeps the ref
            children: layer.children.map { cloneWithNewIDs($0) })
    }

    // MARK: - Grouping

    /// Wraps the given top-level (sibling) layers into a new `.group` layer that
    /// tightly bounds them. Children frames are rebased to the group's origin.
    /// Returns the new group's id, or nil if fewer than one id matched at root.
    @discardableResult
    static func group(_ ids: Set<UUID>, in roots: inout [Layer], named name: String = "Group") -> UUID? {
        // Collect matching root layers in their current z-order.
        let indices = roots.indices.filter { ids.contains(roots[$0].id) }
        guard let firstIndex = indices.first, !indices.isEmpty else { return nil }
        let members = indices.map { roots[$0] }

        // Bounding box in parent space.
        var box = members[0].frame
        for m in members.dropFirst() { box = box.union(m.frame) }

        // Rebase members into group-local space.
        let rebased = members.map { member -> Layer in
            var m = member
            m.frame = VRect(x: member.frame.minX - box.minX, y: member.frame.minY - box.minY,
                            width: member.frame.width, height: member.frame.height)
            return m
        }
        let group = Layer(name: name, kind: .group, frame: box, role: .panel, children: rebased)

        // Remove members (high index first) and insert the group at the
        // front-most member's position.
        let insertionIndex = firstIndex
        for idx in indices.sorted(by: >) { roots.remove(at: idx) }
        let clamped = Swift.min(insertionIndex, roots.count)
        roots.insert(group, at: clamped)
        return group.id
    }

    /// Dissolves a group, lifting its children back into the parent collection
    /// at the group's position, rebasing their frames to parent space.
    /// Returns the ids of the lifted children.
    @discardableResult
    static func ungroup(_ groupID: UUID, in roots: inout [Layer]) -> [UUID] {
        // Only ungroups root-level groups (sufficient for the editor's flow).
        guard let index = roots.firstIndex(where: { $0.id == groupID }), roots[index].kind.isGroupLike else {
            return []
        }
        let group = roots[index]
        let lifted = group.children.map { child -> Layer in
            var c = child
            c.frame = VRect(x: group.frame.minX + child.frame.minX,
                            y: group.frame.minY + child.frame.minY,
                            width: child.frame.width, height: child.frame.height)
            return c
        }
        roots.remove(at: index)
        roots.insert(contentsOf: lifted, at: index)
        return lifted.map { $0.id }
    }

    // MARK: - Absolute z-order

    /// Moves a layer to the front (end) of its sibling list.
    static func bringToFront(_ id: UUID, in roots: inout [Layer]) {
        moveWithinSiblings(id, in: &roots) { siblings, i in
            let layer = siblings.remove(at: i); siblings.append(layer)
        }
    }

    /// Moves a layer to the back (start) of its sibling list.
    static func sendToBack(_ id: UUID, in roots: inout [Layer]) {
        moveWithinSiblings(id, in: &roots) { siblings, i in
            let layer = siblings.remove(at: i); siblings.insert(layer, at: 0)
        }
    }

    /// Applies a reordering closure to the sibling array that contains `id`.
    private static func moveWithinSiblings(_ id: UUID, in roots: inout [Layer],
                                           _ transform: (inout [Layer], Int) -> Void) {
        if let i = roots.firstIndex(where: { $0.id == id }) {
            transform(&roots, i)
            return
        }
        for j in roots.indices {
            moveWithinSiblings(id, in: &roots[j].children, transform)
        }
    }
}
