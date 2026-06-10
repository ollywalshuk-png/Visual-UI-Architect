import Foundation
import VUACore
import LayerEngine

/// Reusable component operations on a Document: create masters from selection,
/// insert/detach instances, propagate master edits, and diagnose problems.
///
/// Conventions:
///   - The component's `master` is a Layer with `componentID == nil` whose
///     frame defines the natural size and whose children are the body.
///   - An instance is a `Layer` whose `componentID == component.id`. Its
///     `children` are a *clone* of the master's children (with fresh ids) so
///     the visual edit/render/codegen paths see real, addressable layers.
///   - Detach simply nils the `componentID` on an instance, breaking the link.
public enum ComponentEngine {

    // MARK: - Diagnostics

    public struct Diagnostic: Hashable, Sendable, Identifiable {
        public enum Severity: Int, Comparable, Sendable {
            case info, warning, error
            public static func < (l: Severity, r: Severity) -> Bool { l.rawValue < r.rawValue }
        }
        public enum Code: String, Sendable {
            case missingMaster
            case circularReference
            case duplicateName
            case invalidName
            case emptyInstance
            case detachedMismatch
        }
        public let id = UUID()
        public var severity: Severity
        public var code: Code
        public var message: String
        public var componentID: UUID?
        public var layerIDs: [UUID]
    }

    // MARK: - Errors

    public enum EngineError: Error, CustomStringConvertible {
        case invalidName
        case noSelection
        case wouldCreateCycle(masterName: String)
        case unknownComponent(UUID)

        public var description: String {
            switch self {
            case .invalidName: return "Component name must not be empty."
            case .noSelection: return "Nothing selected to convert into a component."
            case .wouldCreateCycle(let name): return "Inserting that instance would create a circular reference in '\(name)'."
            case .unknownComponent(let id): return "Unknown component: \(id.uuidString)."
            }
        }
    }

    // MARK: - Create

    /// Builds a component master from a list of layers and registers it in the
    /// document. The layers are removed from their current location at the call
    /// site (caller decides) — this function only constructs the master + a
    /// fresh instance that can replace them.
    public static func makeComponent(
        named rawName: String,
        from layers: [Layer],
        category: String? = nil
    ) throws -> (component: Component, instance: Layer) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw EngineError.invalidName }
        guard !layers.isEmpty else { throw EngineError.noSelection }

        // Bounding box for the master frame; rebase children into local space.
        var box = layers[0].frame
        for l in layers.dropFirst() { box = box.union(l.frame) }
        let masterChildren = layers.map { layer -> Layer in
            var rebased = LayerTree.cloneWithNewIDs(layer)
            rebased.frame = VRect(
                x: layer.frame.minX - box.minX,
                y: layer.frame.minY - box.minY,
                width: layer.frame.width, height: layer.frame.height)
            return rebased
        }
        let master = Layer(
            name: name,
            kind: .group,
            frame: VRect(origin: .zero, size: box.size),
            role: .panel,
            children: masterChildren)
        let component = Component(name: name, category: category, master: master)

        let instance = makeInstance(of: component, at: box.origin)
        return (component, instance)
    }

    /// Builds an instance Layer referencing `component`, placed at `origin`.
    /// The instance carries a fresh clone of the master's body so the canvas
    /// can hit-test and render real layers; ids are unique on every call.
    public static func makeInstance(of component: Component, at origin: VPoint) -> Layer {
        let body = component.master.children.map { LayerTree.cloneWithNewIDs($0) }
        return Layer(
            id: UUID(),
            name: component.name,
            kind: .group,
            frame: VRect(origin: origin, size: component.master.frame.size),
            role: component.master.role,
            children: body
        ).withComponentID(component.id)
    }

    // MARK: - Propagation

    /// Rewrites every instance of `component.id` so its body matches the
    /// component's master (preserving instance position). Returns updated roots
    /// and the number of instances re-synced.
    @discardableResult
    public static func propagateMaster(_ component: Component, in roots: inout [Layer]) -> Int {
        var updated = 0
        rewriteTree(&roots) { layer in
            guard layer.componentID == component.id else { return }
            layer.name = component.name
            layer.frame.size = component.master.frame.size
            layer.children = component.master.children.map { LayerTree.cloneWithNewIDs($0) }
            updated += 1
        }
        return updated
    }

    /// Counts instances of each component across the layer tree.
    public static func instanceCounts(in roots: [Layer]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for layer in roots.flatMap({ $0.flattened() }) {
            if let cid = layer.componentID { counts[cid, default: 0] += 1 }
        }
        return counts
    }

    // MARK: - Detach

    /// Removes the component link on a single layer (and bumps a fresh id),
    /// leaving its body intact. Returns true if anything changed.
    @discardableResult
    public static func detach(_ layerID: UUID, in roots: inout [Layer]) -> Bool {
        var detached = false
        rewriteTree(&roots) { layer in
            guard layer.id == layerID, layer.componentID != nil else { return }
            layer.componentID = nil
            detached = true
        }
        return detached
    }

    // MARK: - Safety: cycle detection

    /// True when inserting an instance of `component` inside `container` would
    /// produce a self-referential master/instance loop. The directed edge we'd
    /// add is `container → component`; a cycle exists iff `container` is
    /// already reachable from the inserted master's subtree.
    public static func wouldCreateCycle(insertingMaster componentID: UUID,
                                        intoMaster containerID: UUID,
                                        components: [Component]) -> Bool {
        if componentID == containerID { return true }
        return references(componentID: containerID, fromMasterOf: componentID,
                          components: components, visited: [])
    }

    /// Walks the master of `source` (and any component it references) looking
    /// for a reference to `target`. `visited` guards against pre-existing cycles.
    private static func references(componentID target: UUID,
                                   fromMasterOf source: UUID,
                                   components: [Component],
                                   visited: Set<UUID>) -> Bool {
        guard !visited.contains(source) else { return false }
        var seen = visited
        seen.insert(source)
        guard let master = components.first(where: { $0.id == source })?.master else { return false }
        for layer in master.flattened() {
            guard let cid = layer.componentID else { continue }
            if cid == target { return true }
            if references(componentID: target, fromMasterOf: cid,
                          components: components, visited: seen) {
                return true
            }
        }
        return false
    }

    // MARK: - Diagnostics

    /// Runs the full component-system diagnostics for a document.
    public static func diagnose(_ document: Document) -> [Diagnostic] {
        var out: [Diagnostic] = []
        let masterIDs = Set(document.components.map { $0.id })

        // Names.
        var seenNames: [String: UUID] = [:]
        for component in document.components {
            let trimmed = component.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                out.append(.init(severity: .error, code: .invalidName,
                                 message: "Component has an empty name.",
                                 componentID: component.id, layerIDs: []))
            }
            if let existing = seenNames[trimmed.lowercased()], existing != component.id {
                out.append(.init(severity: .warning, code: .duplicateName,
                                 message: "Duplicate component name '\(trimmed)'.",
                                 componentID: component.id, layerIDs: []))
            } else {
                seenNames[trimmed.lowercased()] = component.id
            }
        }

        // Cycles among masters.
        for component in document.components {
            for layer in component.master.flattened() {
                if let cid = layer.componentID,
                   wouldCreateCycle(insertingMaster: cid, intoMaster: component.id, components: document.components) {
                    out.append(.init(severity: .error, code: .circularReference,
                                     message: "Component '\(component.name)' contains a circular reference.",
                                     componentID: component.id, layerIDs: [layer.id]))
                    break
                }
            }
        }

        // Instance integrity: missing master / empty body.
        for layer in document.allLayers {
            guard let cid = layer.componentID else { continue }
            if !masterIDs.contains(cid) {
                out.append(.init(severity: .error, code: .missingMaster,
                                 message: "Instance '\(layer.name)' references a missing component.",
                                 componentID: cid, layerIDs: [layer.id]))
                continue
            }
            if layer.children.isEmpty {
                out.append(.init(severity: .info, code: .emptyInstance,
                                 message: "Instance '\(layer.name)' has no children — re-sync from master.",
                                 componentID: cid, layerIDs: [layer.id]))
            }
        }
        return out
    }

    // MARK: - Tree rewrite helper

    /// Walks the tree, allowing the closure to mutate each layer in place.
    private static func rewriteTree(_ roots: inout [Layer], _ visit: (inout Layer) -> Void) {
        for i in roots.indices {
            var layer = roots[i]
            visit(&layer)
            rewriteTree(&layer.children, visit)
            roots[i] = layer
        }
    }
}

// MARK: - Small convenience

private extension Layer {
    /// Returns a copy with `componentID` set — the `id` is `let`, so we
    /// rebuild via the initializer instead of in-place mutation.
    func withComponentID(_ cid: UUID?) -> Layer {
        Layer(
            id: id, name: name, kind: kind, frame: frame, style: style,
            text: text, assetID: assetID, isVisible: isVisible, isLocked: isLocked,
            labelColor: labelColor, constraints: constraints, binding: binding,
            control: control,
            role: role, notes: notes, tags: tags,
            isCollapsed: isCollapsed, isAccessibilityHidden: isAccessibilityHidden,
            line: line, polygon: polygon, mask: mask, clipShape: clipShape,
            componentID: cid,
            children: children)
    }
}
