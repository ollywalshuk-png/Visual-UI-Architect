import Foundation
import VUACore
import LayerEngine
import PresetEngine

/// Phase 7 editing: clipboard, grouping, z-order, selection, shape/preset
/// insertion. Builds on the store's `mutate`/undo machinery.
extension DocumentStore {

    // In-memory clipboard (layer subtrees with their original ids; cloned on paste).
    private static var clipboard: [Layer] = []

    // MARK: - Clipboard

    var canPaste: Bool { !DocumentStore.clipboard.isEmpty }

    func copySelection() {
        let layers = selection.compactMap { document.layer(id: $0) }
        guard !layers.isEmpty else { return }
        DocumentStore.clipboard = layers
    }

    func cutSelection() {
        copySelection()
        deleteSelection()
    }

    /// Pastes clipboard layers with fresh ids, offset slightly, into the same
    /// parent as the current selection (or root). Selects the pasted layers.
    func paste(offset: VPoint = VPoint(x: 16, y: 16)) {
        let items = DocumentStore.clipboard
        guard !items.isEmpty else { return }
        var newIDs: Set<UUID> = []
        let parentID: UUID? = canSelectSingle?.isContainer == true ? canSelectSingle?.id : nil
        mutate { doc in
            for item in items {
                var clone = LayerTree.cloneWithNewIDs(item)
                clone.frame.origin.x += offset.x
                clone.frame.origin.y += offset.y
                newIDs.insert(clone.id)
                LayerTree.insert(clone, into: &doc.roots, parentID: parentID)
            }
        }
        selection = newIDs
    }

    // MARK: - Grouping

    var canGroup: Bool {
        // Group only when 2+ root-level layers are selected.
        selection.count >= 2 && selection.allSatisfy { id in
            document.roots.contains { $0.id == id }
        }
    }

    func groupSelection() {
        guard canGroup else { return }
        let ids = selection
        var newGroup: UUID?
        mutate { doc in newGroup = LayerTree.group(ids, in: &doc.roots) }
        if let newGroup { selection = [newGroup] }
    }

    var canUngroup: Bool {
        guard let layer = canSelectSingle else { return false }
        return layer.kind.isGroupLike && !layer.children.isEmpty
    }

    func ungroupSelection() {
        guard let id = selection.first else { return }
        var lifted: [UUID] = []
        mutate { doc in lifted = LayerTree.ungroup(id, in: &doc.roots) }
        selection = Set(lifted)
    }

    // MARK: - Z-order (multi)

    func bringSelectionToFront() {
        let ids = selection
        mutate { doc in for id in ids { LayerTree.bringToFront(id, in: &doc.roots) } }
    }

    func sendSelectionToBack() {
        let ids = selection
        mutate { doc in for id in ids.sorted(by: { $0.uuidString > $1.uuidString }) { LayerTree.sendToBack(id, in: &doc.roots) } }
    }

    func bringSelectionForward() {
        let ids = selection
        mutate { doc in for id in ids { LayerTree.reorder(id, towardFront: true, in: &doc.roots) } }
    }

    func sendSelectionBackward() {
        let ids = selection
        mutate { doc in for id in ids { LayerTree.reorder(id, towardFront: false, in: &doc.roots) } }
    }

    // MARK: - Selection commands

    func selectAll() { selection = Set(document.roots.map { $0.id }) }
    func deselectAll() { selection = [] }

    func invertSelection() {
        let all = Set(document.roots.map { $0.id })
        selection = all.subtracting(selection)
    }

    func selectChildren() {
        guard let layer = canSelectSingle, !layer.children.isEmpty else { return }
        selection = Set(layer.children.map { $0.id })
    }

    func selectParent() {
        guard let id = selection.first else { return }
        // Find the parent of `id`.
        for root in document.roots {
            if root.children.contains(where: { $0.id == id }) { selection = [root.id]; return }
            if let parent = findParent(of: id, in: root) { selection = [parent]; return }
        }
    }

    private func findParent(of id: UUID, in layer: Layer) -> UUID? {
        for child in layer.children {
            if child.id == id { return layer.id }
            if let p = findParent(of: id, in: child) { return p }
        }
        return nil
    }

    // MARK: - Visibility / lock (multi)

    func setSelectionVisible(_ visible: Bool) {
        let ids = selection
        mutate { doc in for id in ids { LayerTree.update(id, in: &doc.roots) { $0.isVisible = visible } } }
    }

    func setSelectionLocked(_ locked: Bool) {
        let ids = selection
        mutate { doc in for id in ids { LayerTree.update(id, in: &doc.roots) { $0.isLocked = locked } } }
    }

    // MARK: - Shape / vector insertion

    /// Inserts a shape layer of the given kind, centered on the canvas.
    func addShape(_ kind: ShapeKind) {
        addLayer(.shape(kind))
        // Give shapes a visible default fill.
        if let id = selection.first {
            mutate { LayerTree.update(id, in: &$0.roots) { l in
                if l.style.backgroundColor == nil { l.style.backgroundColor = VColor(hex: "#3A3A3C") }
                l.role = .decoration
            } }
        }
    }

    /// Inserts a horizontal line across the canvas center.
    func addLine() {
        addLayer(.line)
        if let id = selection.first {
            mutate { LayerTree.update(id, in: &$0.roots) { l in
                l.line = LineSpec(start: VPoint(x: 0, y: l.frame.height / 2),
                                  end: VPoint(x: l.frame.width, y: l.frame.height / 2))
                l.style.borderColor = .white
                l.style.borderWidth = 2
                l.role = .decoration
            } }
        }
    }

    func addPolygon(sides: Int = 6, star: Bool = false) {
        addLayer(.polygon)
        if let id = selection.first {
            mutate { LayerTree.update(id, in: &$0.roots) { l in
                l.polygon = PolygonSpec(sides: sides, starInnerRatio: star ? 0.4 : nil)
                if l.style.backgroundColor == nil { l.style.backgroundColor = VColor(hex: "#0A84FF") }
                l.role = .decoration
            } }
        }
    }

    func addGradient(_ kind: GradientSpec.Kind = .linear) {
        addLayer(.gradient)
        if let id = selection.first {
            mutate { LayerTree.update(id, in: &$0.roots) { l in
                l.style.gradient = GradientSpec(kind: kind)
                l.role = .background
            } }
        }
    }

    // MARK: - Inspector helpers (Phase 7 attributes)

    func updateSelectedStyle(_ transform: @escaping (inout LayerStyle) -> Void) {
        guard let id = selection.first else { return }
        mutate { LayerTree.update(id, in: &$0.roots) { transform(&$0.style) } }
    }

    func setSelectedRole(_ role: LayerRole?) {
        updateSelectedLayer { $0.role = role }
    }

    func setSelectedNotes(_ notes: String) {
        updateSelectedLayer { $0.notes = notes.isEmpty ? nil : notes }
    }

    // MARK: - Presets

    /// Inserts a preset's layer subtree centered on the canvas. New ids are
    /// assigned so repeated insertions don't collide.
    func insertPreset(_ preset: Preset) {
        let canvas = document.canvasSize
        // Build at origin to learn its size, then center it.
        let probe = preset.build(.zero)
        let origin = VPoint(x: max(0, (canvas.width - probe.frame.width) / 2),
                            y: max(0, (canvas.height - probe.frame.height) / 2))
        let layer = LayerTree.cloneWithNewIDs(preset.build(origin))
        mutate { LayerTree.insert(layer, into: &$0.roots, parentID: nil) }
        selection = [layer.id]
        repositoryStatus = "Inserted preset “\(preset.name)”."
    }

    /// Inserts an advanced control preset (knob/fader/slider/button/toggle),
    /// centered on the canvas with fresh ids.
    func insertControlPreset(_ preset: ControlPreset) {
        let canvas = document.canvasSize
        let origin = VPoint(x: max(0, (canvas.width - preset.size.width) / 2),
                            y: max(0, (canvas.height - preset.size.height) / 2))
        let layer = LayerTree.cloneWithNewIDs(preset.makeLayer(at: origin))
        mutate { LayerTree.insert(layer, into: &$0.roots, parentID: nil) }
        selection = [layer.id]
        repositoryStatus = "Inserted “\(preset.name)”."
    }

    /// Inserts a functional control asset (Phase 19) centered on the canvas.
    func insertControlAsset(_ asset: ControlAsset) {
        let canvas = document.canvasSize
        let origin = VPoint(x: max(0, (canvas.width - asset.defaultSize.width) / 2),
                            y: max(0, (canvas.height - asset.defaultSize.height) / 2))
        let layer = LayerTree.cloneWithNewIDs(asset.makeLayer(at: origin))
        mutate { LayerTree.insert(layer, into: &$0.roots, parentID: nil) }
        selection = [layer.id]
        repositoryStatus = "Inserted control asset “\(asset.name)”."
    }
}
