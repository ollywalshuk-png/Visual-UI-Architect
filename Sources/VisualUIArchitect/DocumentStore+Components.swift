import Foundation
import VUACore
import LayerEngine
import ComponentEngine

/// Component-system store actions: create from selection, insert instance,
/// detach, rename, delete, update-all. All edits go through `mutate` so they
/// participate in undo/redo and dirty-tracking.
extension DocumentStore {

    // MARK: - Queries

    var components: [Component] { document.components }

    func componentInstanceCounts() -> [UUID: Int] {
        ComponentEngine.instanceCounts(in: document.roots)
    }

    func componentDiagnostics() -> [ComponentEngine.Diagnostic] {
        ComponentEngine.diagnose(document)
    }

    func variants(for componentID: UUID) -> [ComponentVariant] {
        document.component(id: componentID)?.variants ?? []
    }

    // MARK: - Create

    /// Creates a master from the current selection, registers it on the
    /// document, removes the selected layers, and drops a fresh instance in
    /// their place. No-op if the selection is empty.
    @discardableResult
    func createComponentFromSelection(named rawName: String, category: String? = nil) -> UUID? {
        let layers = selection.compactMap { document.layer(id: $0) }
        guard !layers.isEmpty else {
            repositoryStatus = "Select layers first to make a component."
            return nil
        }
        do {
            let made = try ComponentEngine.makeComponent(named: rawName, from: layers, category: category)
            let ids = selection
            mutate { doc in
                // Remove the source layers, add the master, insert the instance.
                for id in ids { LayerTree.remove(id, from: &doc.roots) }
                doc.components.append(made.component)
                LayerTree.insert(made.instance, into: &doc.roots, parentID: nil)
            }
            selection = [made.instance.id]
            repositoryStatus = "Created component '\(made.component.name)'."
            return made.component.id
        } catch {
            repositoryStatus = "Component create failed: \(error)"
            return nil
        }
    }

    // MARK: - Insert / detach

    /// Inserts a fresh instance of a component at the canvas centre.
    func insertComponentInstance(_ componentID: UUID) {
        guard let component = document.component(id: componentID) else {
            repositoryStatus = "Component not found."
            return
        }
        let canvas = document.canvasSize
        let origin = VPoint(
            x: max(0, (canvas.width - component.master.frame.width) / 2),
            y: max(0, (canvas.height - component.master.frame.height) / 2))
        let instance = ComponentEngine.makeInstance(of: component, at: origin)
        mutate { LayerTree.insert(instance, into: &$0.roots, parentID: nil) }
        selection = [instance.id]
        repositoryStatus = "Inserted instance of '\(component.name)'."
    }

    func switchSelectedComponentVariant(to variantID: UUID?) {
        guard let id = selection.first,
              let layer = document.layer(id: id),
              let componentID = layer.componentID,
              let component = document.component(id: componentID) else {
            repositoryStatus = "Select a component instance first."
            return
        }
        var ok = false
        mutate { doc in ok = ComponentEngine.switchVariant(instanceID: id, to: variantID, component: component, in: &doc.roots) }
        repositoryStatus = ok ? "Switched component variant." : "Variant switch failed."
    }

    func addOverrideToSelectedComponent(property: String, value: String) {
        guard let id = selection.first else { return }
        var ok = false
        mutate { doc in
            ok = ComponentEngine.addOverride(
                ComponentOverride(property: property, valueDescription: value),
                to: id, in: &doc.roots)
        }
        repositoryStatus = ok ? "Added local override." : "Override blocked by locked property."
    }

    func lockSelectedComponentProperty(_ property: String) {
        guard let id = selection.first else { return }
        var ok = false
        mutate { doc in ok = ComponentEngine.lockProperty(property, on: id, in: &doc.roots) }
        repositoryStatus = ok ? "Locked component property." : "Property lock failed."
    }

    /// Detaches the currently-selected layer from its component master.
    func detachSelectedComponentInstance() {
        guard let id = selection.first else { return }
        var ok = false
        mutate { doc in ok = ComponentEngine.detach(id, in: &doc.roots) }
        repositoryStatus = ok ? "Instance detached." : "Selection is not a component instance."
    }

    // MARK: - Master propagation

    /// Re-syncs every instance of `componentID` to the master, bumping version.
    func updateInstancesOfComponent(_ componentID: UUID) {
        guard let index = document.components.firstIndex(where: { $0.id == componentID }) else { return }
        var count = 0
        mutate { doc in
            doc.components[index].version += 1
            count = ComponentEngine.propagateMaster(doc.components[index], in: &doc.roots)
        }
        repositoryStatus = "Updated \(count) instance(s)."
    }

    // MARK: - Library management

    func renameComponent(_ componentID: UUID, to newName: String) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        mutate { doc in
            if let i = doc.components.firstIndex(where: { $0.id == componentID }) {
                doc.components[i].name = name
            }
        }
    }

    func createStandardVariants(for componentID: UUID) {
        mutate { doc in
            guard let index = doc.components.firstIndex(where: { $0.id == componentID }) else { return }
            let variants = ComponentEngine.standardButtonVariants(for: doc.components[index])
            let existing = Set(doc.components[index].variants.map { $0.name })
            for variant in variants where !existing.contains(variant.name) {
                doc.components[index].variants.append(variant)
            }
        }
        repositoryStatus = "Created standard component variants."
    }

    /// Deletes a component. If `detachInstances` is true, existing instances
    /// have their `componentID` cleared so they keep rendering; otherwise the
    /// instances remain but will show a "missing master" diagnostic.
    func deleteComponent(_ componentID: UUID, detachInstances: Bool = true) {
        mutate { doc in
            if detachInstances {
                ComponentEngine_detachAll(componentID, in: &doc.roots)
            }
            doc.components.removeAll { $0.id == componentID }
        }
        repositoryStatus = "Component deleted."
    }
}

/// File-private helper that walks every layer detaching matching instances.
/// Kept here so `deleteComponent` can stay a single `mutate`.
private func ComponentEngine_detachAll(_ componentID: UUID, in roots: inout [Layer]) {
    for i in roots.indices {
        if roots[i].componentID == componentID {
            // Rebuild the layer with componentID = nil (id is `let`).
            roots[i] = withoutComponentID(roots[i])
        }
        ComponentEngine_detachAll(componentID, in: &roots[i].children)
    }
}

private func withoutComponentID(_ layer: Layer) -> Layer {
    Layer(
        id: layer.id, name: layer.name, kind: layer.kind, frame: layer.frame, style: layer.style,
        text: layer.text, assetID: layer.assetID, isVisible: layer.isVisible, isLocked: layer.isLocked,
        labelColor: layer.labelColor, constraints: layer.constraints, binding: layer.binding,
        control: layer.control,
        role: layer.role, notes: layer.notes, tags: layer.tags,
        isCollapsed: layer.isCollapsed, isAccessibilityHidden: layer.isAccessibilityHidden,
        line: layer.line, polygon: layer.polygon, vectorPath: layer.vectorPath, mask: layer.mask, clipShape: layer.clipShape,
        assetTransform: layer.assetTransform,
        rasterPaint: layer.rasterPaint,
        componentID: nil,
        componentVariantID: nil,
        componentOverrides: [],
        lockedComponentProperties: [],
        children: layer.children)
}
