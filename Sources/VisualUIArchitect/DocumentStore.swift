import Foundation
import SwiftUI
import VUACore
import LayerEngine
import CodeGenEngine
import ValidationEngine
import PreviewEngine
import AIEngine
import RepositoryEngine
import WorkspaceEngine
import BuildIntelligenceEngine
import ControlBehaviourEngine

/// The single observable source of truth for the editor (MVVM view model).
/// Holds the document, selection, undo/redo history, and derived state.
@MainActor
final class DocumentStore: ObservableObject {
    @Published private(set) var document: Document
    @Published var selection: Set<UUID> = []
    @Published private(set) var validation: ValidationReport = ValidationReport(issues: [])
    @Published var snapGuides: [Snapping.Guide] = []
    @Published var editorMode: EditorInteractionMode = .build
    @Published var previewState = InteractionPreviewState()

    // Repository round-trip state (see DocumentStore+Repository.swift).
    @Published var repositoryRoot: URL?
    @Published var repositoryFiles: [RepositoryFile] = []
    @Published var repositoryGraphIndex: RepositoryGraphIndex?
    @Published var openedFileName: String?
    // Phase 18 — existing-UI import provenance (for round-trip apply guard).
    @Published var importedSourcePath: String?
    @Published var importedSourceHash: String?
    @Published var importedViewName: String?
    @Published var importedSourceHasAnchors: Bool?
    @Published var importedAt: Date?
    @Published var repositoryStatus: String = ""
    var fileWatcher: FileWatcher?
    /// Repeating autosave timer (see DocumentStore+Persistence.swift).
    var autosaveTimer: Timer?
    /// Most recent workspace-safety resolution (see DocumentStore+Workspace.swift).
    @Published var workspaceContext: WorkspaceContext?
    /// Most recent build-intelligence resolution (see DocumentStore+Build.swift).
    @Published var buildContext: BuildContext?

    // Persistence state (see DocumentStore+Persistence.swift).
    /// The .vuaproj bundle URL backing the current document, if saved.
    @Published var documentURL: URL?
    /// True when the document has unsaved changes since the last save/load.
    @Published private(set) var isDirty: Bool = false

    // Set when a close is requested while dirty — MainWindow shows the prompt.
    @Published var closeConfirmPending: Bool = false
    // Set when open/new is requested while dirty — MainWindow shows the prompt.
    @Published var pendingDirtyAction: PendingDirtyAction?

    /// A document-switching action deferred until the user resolves unsaved work.
    enum PendingDirtyAction: Equatable {
        case openPanel
        case open(URL)
        case newDocument
    }

    // Canvas workflow state (Phase 8) — ephemeral guides in canvas coordinates.
    @Published var verticalGuides: [Double] = []     // x positions
    @Published var horizontalGuides: [Double] = []   // y positions

    func addVerticalGuide(_ x: Double) {
        guard canEditDocument else { return }
        verticalGuides.append(x)
    }
    func addHorizontalGuide(_ y: Double) {
        guard canEditDocument else { return }
        horizontalGuides.append(y)
    }
    func clearGuides() {
        guard canEditDocument else { return }
        verticalGuides = []
        horizontalGuides = []
    }

    // Undo/redo via document snapshots. Simple, correct, and storage-cheap for
    // documents up to many thousands of layers.
    private var undoStack: [Document] = []
    private var redoStack: [Document] = []
    private let maxHistory = 200

    private let codeGen = CodeGenService()
    private let validator = ValidationService()
    private let previewBuilder = PreviewBuilder()

    init(document: Document = .sample) {
        self.document = document
        revalidate()
    }

    // MARK: - Derived

    var renderModel: RenderModel { previewBuilder.build(document) }
    var canSelectSingle: Layer? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return document.layer(id: id)
    }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isTestMode: Bool { editorMode == .test }
    var canEditDocument: Bool { editorMode.allowsLayoutEditing }

    // MARK: - Build/Test mode

    func switchEditorMode(_ mode: EditorInteractionMode) {
        guard editorMode != mode else { return }
        if isInteracting { endInteraction() }
        editorMode = mode
        previewState.switchMode(mode)
        snapGuides = []
        if mode == .test {
            repositoryStatus = "Test Mode: layout is locked; controls are interactive."
        } else {
            previewState.activeLayerID = nil
            repositoryStatus = "Build Mode: layout and styling edits enabled."
        }
    }

    func toggleEditorMode() {
        switchEditorMode(editorMode == .build ? .test : .build)
    }

    func exitActivePreviewInteraction() {
        previewState.activeLayerID = nil
    }

    func resetPreviewValues() {
        previewState.resetAll()
        repositoryStatus = "Reset Test Mode preview values."
    }

    func previewResult(for layer: Layer) -> InteractionPreviewResult? {
        InteractionPreviewEngine.previewResult(for: layer, state: previewState)
    }

    func setPreviewValue(_ value: Double, for layer: Layer) {
        InteractionPreviewEngine.setValue(value, for: layer, in: &previewState)
        selection = [layer.id]
    }

    func resetPreviewValue(for layer: Layer) {
        InteractionPreviewEngine.resetValue(for: layer, in: &previewState)
    }

    func applyPreviewValueToSelectedDefault() {
        guard let id = selection.first,
              let layer = document.layer(id: id),
              var control = layer.control,
              let value = previewState.values[id] else { return }
        undoStack.append(document)
        if undoStack.count > maxHistory { undoStack.removeFirst() }
        redoStack.removeAll()
        control.defaultValue = control.clamp(value)
        var copy = document
        LayerTree.update(id, in: &copy.roots) { $0.control = control }
        document = copy
        isDirty = true
        revalidate()
        repositoryStatus = "Applied Test Mode preview value to \(layer.name)."
    }

    // MARK: - Mutation with history

    /// Applies a mutation, recording an undo checkpoint first.
    func mutate(_ action: (inout Document) -> Void) {
        guard canEditDocument else {
            repositoryStatus = "Switch to Build Mode to edit the document."
            return
        }
        undoStack.append(document)
        if undoStack.count > maxHistory { undoStack.removeFirst() }
        redoStack.removeAll()
        var copy = document
        action(&copy)
        document = copy
        isDirty = true
        revalidate()
    }

    /// A live mutation (e.g. during a drag) that should not create a new
    /// checkpoint each frame. Call `beginInteraction()` once before the drag.
    func mutateLive(_ action: (inout Document) -> Void) {
        guard canEditDocument else { return }
        var copy = document
        action(&copy)
        document = copy
    }

    // Live interaction (drag/resize). A single checkpoint is captured at the
    // start; per-frame edits derive from baseline frames so cumulative gesture
    // translations apply correctly.
    private var interactionCheckpoint: Document?
    private var baselineFrames: [UUID: VRect] = [:]
    private(set) var isInteracting = false

    func beginInteractionIfNeeded() {
        guard canEditDocument else { return }
        guard !isInteracting else { return }
        isInteracting = true
        interactionCheckpoint = document
        baselineFrames = [:]
        for id in selection {
            if let layer = document.layer(id: id) { baselineFrames[id] = layer.frame }
        }
    }

    func endInteraction() {
        if let cp = interactionCheckpoint, cp != document {
            undoStack.append(cp)
            if undoStack.count > maxHistory { undoStack.removeFirst() }
            redoStack.removeAll()
            revalidate()
        }
        interactionCheckpoint = nil
        baselineFrames = [:]
        isInteracting = false
        snapGuides = []
    }

    /// Moves all selected layers by a canvas-space delta from their baseline.
    func moveSelected(byCanvasDelta delta: VPoint) {
        guard canEditDocument else { return }
        mutateLive { doc in
            for (id, base) in baselineFrames {
                LayerTree.update(id, in: &doc.roots) {
                    $0.frame.origin = VPoint(x: base.origin.x + delta.x, y: base.origin.y + delta.y)
                }
            }
        }
    }

    /// Resizes the primary selection by dragging `handle` from its baseline.
    func resizeSelected(handle: (VRect) -> VRect) {
        guard canEditDocument else { return }
        guard let id = selection.first, let base = baselineFrames[id] else { return }
        mutateLive { doc in
            LayerTree.update(id, in: &doc.roots) { $0.frame = handle(base) }
        }
    }

    /// Baseline (gesture-start) frame for a layer, if interacting.
    func baselineFrame(_ id: UUID) -> VRect? { baselineFrames[id] }

    func undo() {
        guard canEditDocument else { return }
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(document)
        document = prev
        isDirty = true
        revalidate()
    }

    func redo() {
        guard canEditDocument else { return }
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        isDirty = true
        revalidate()
    }

    /// Replaces the entire document atomically (used by file open) and resets
    /// undo/redo. Marks the document clean and records the backing URL.
    func loadDocument(_ doc: Document, fromURL url: URL?) {
        undoStack.removeAll()
        redoStack.removeAll()
        snapGuides = []
        verticalGuides = []
        horizontalGuides = []
        selection = []
        editorMode = .build
        previewState.resetAll()
        document = doc
        documentURL = url
        isDirty = false
        revalidate()
    }

    /// Marks the document clean (e.g. after a successful save).
    func markClean() { isDirty = false }

    /// Marks the document dirty (e.g. after restoring recovery/snapshot).
    func markDirty() { isDirty = true }

    private func revalidate() {
        validation = validator.validate(document)
    }

    // MARK: - Layer operations

    func addLayer(_ kind: LayerKind) {
        let size = defaultSize(for: kind)
        let canvas = document.canvasSize
        let layer = Layer(
            name: kind.displayName,
            kind: kind,
            frame: VRect(x: (canvas.width - size.width) / 2,
                         y: (canvas.height - size.height) / 2,
                         width: size.width, height: size.height),
            style: defaultStyle(for: kind),
            text: defaultText(for: kind),
            control: defaultControl(for: kind))
        // Insert into the single selected container, else at root.
        let parentID: UUID? = canSelectSingle?.isContainer == true ? canSelectSingle?.id : nil
        mutate { LayerTree.insert(layer, into: &$0.roots, parentID: parentID) }
        selection = [layer.id]
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        let ids = selection
        mutate { doc in for id in ids { LayerTree.remove(id, from: &doc.roots) } }
        selection = []
    }

    func duplicateSelection() {
        guard !selection.isEmpty else { return }
        var newIDs: Set<UUID> = []
        mutate { doc in
            for id in selection {
                guard let layer = doc.layer(id: id) else { continue }
                var copy = deepCopy(layer)
                copy.frame.origin.x += 16
                copy.frame.origin.y += 16
                copy.name += " copy"
                newIDs.insert(copy.id)
                let path = LayerTree.indexPath(of: id, in: doc.roots)
                // Insert as a sibling at root level (parent resolution kept simple).
                _ = path
                LayerTree.insert(copy, into: &doc.roots, parentID: nil)
            }
        }
        selection = newIDs
    }

    func setVisibility(_ id: UUID, _ visible: Bool) {
        mutate { LayerTree.update(id, in: &$0.roots) { $0.isVisible = visible } }
    }

    func setLocked(_ id: UUID, _ locked: Bool) {
        mutate { LayerTree.update(id, in: &$0.roots) { $0.isLocked = locked } }
    }

    /// Moves a layer one step toward the front (drawn on top) within its siblings.
    func reorderLayerTowardFront(_ id: UUID) {
        mutate { LayerTree.reorder(id, towardFront: true, in: &$0.roots) }
    }

    /// Moves a layer one step toward the back (drawn underneath) within its siblings.
    func reorderLayerTowardBack(_ id: UUID) {
        mutate { LayerTree.reorder(id, towardFront: false, in: &$0.roots) }
    }

    func canReorderLayer(_ id: UUID, towardFront: Bool) -> Bool {
        LayerTree.canReorder(id, towardFront: towardFront, in: document.roots)
    }

    func rename(_ id: UUID, to name: String) {
        mutate { LayerTree.update(id, in: &$0.roots) { $0.name = name } }
    }

    func updateSelectedLayer(_ transform: @escaping (inout Layer) -> Void) {
        guard let id = selection.first else { return }
        mutate { LayerTree.update(id, in: &$0.roots, transform) }
    }

    func alignSelection(_ edge: LayerEngine.Alignment.Edge) {
        let frames = selectedFrames()
        guard frames.count > 1 else { return }
        let result = LayerEngine.Alignment.align(frames, to: edge)
        applyFrames(result)
    }

    func distributeSelection(_ axis: LayerEngine.Alignment.Axis) {
        let frames = selectedFrames()
        guard frames.count > 2 else { return }
        let result = LayerEngine.Alignment.distribute(frames, along: axis)
        applyFrames(result)
    }

    private func selectedFrames() -> [UUID: VRect] {
        var out: [UUID: VRect] = [:]
        for id in selection { if let l = document.layer(id: id) { out[id] = l.frame } }
        return out
    }

    private func applyFrames(_ frames: [UUID: VRect]) {
        mutate { doc in
            for (id, f) in frames { LayerTree.update(id, in: &doc.roots) { $0.frame = f } }
        }
    }

    func setDevice(_ device: DeviceProfile) {
        mutate { $0.activeDevice = device }
    }

    func setOrientation(_ o: DeviceProfile.Orientation) {
        mutate { $0.activeOrientation = o }
    }

    // MARK: - Code generation

    func generateCode() -> String {
        (try? codeGen.generate(document).contents) ?? "// Generation failed."
    }

    // MARK: - Defaults

    private func deepCopy(_ layer: Layer) -> Layer {
        // Preserve every field; assign fresh ids down the tree (LayerEngine clone).
        LayerTree.cloneWithNewIDs(layer)
    }

    private func defaultSize(for kind: LayerKind) -> VSize {
        switch kind {
        case .button: return VSize(width: 120, height: 44)
        case .label, .text: return VSize(width: 160, height: 24)
        case .slider: return VSize(width: 200, height: 28)
        case .knob: return VSize(width: 64, height: 64)
        case .fader: return VSize(width: 40, height: 180)
        case .meter: return VSize(width: 24, height: 120)
        case .toggle: return VSize(width: 80, height: 32)
        case .image: return VSize(width: 120, height: 120)
        case .panel, .container, .background, .group: return VSize(width: 240, height: 160)
        case .shape(let s): return s == .divider ? VSize(width: 200, height: 2) : VSize(width: 120, height: 80)
        case .line: return VSize(width: 160, height: 2)
        case .vectorPath: return VSize(width: 160, height: 120)
        case .polygon: return VSize(width: 90, height: 90)
        case .gradient: return VSize(width: 240, height: 120)
        case .mask: return VSize(width: 120, height: 120)
        case .control, .custom: return VSize(width: 100, height: 100)
        }
    }

    private func defaultStyle(for kind: LayerKind) -> LayerStyle {
        switch kind {
        case .button:
            return LayerStyle(backgroundColor: VColor(hex: "#0A84FF"),
                              foregroundColor: .white, cornerRadius: 8, fontSize: 15, fontWeight: .semibold)
        case .panel, .container:
            return LayerStyle(backgroundColor: VColor(hex: "#2C2C2E"), cornerRadius: 12)
        case .label, .text:
            return LayerStyle(foregroundColor: .white, fontSize: 15)
        case .knob, .fader, .meter, .control:
            return LayerStyle(backgroundColor: VColor(hex: "#3A3A3C"), cornerRadius: 8)
        case .vectorPath:
            return LayerStyle(backgroundColor: nil, foregroundColor: .white, borderColor: .white, borderWidth: 2)
        default:
            return .default
        }
    }

    /// Sensible AU parameter defaults for newly-added plugin controls.
    private func defaultControl(for kind: LayerKind) -> ControlMetadata? {
        switch kind {
        case .knob:
            return ControlMetadata(parameterID: "cutoff", displayName: "Cutoff",
                                   minValue: 20, maxValue: 20000, defaultValue: 1000, unit: .hertz)
        case .fader:
            return ControlMetadata(parameterID: "level", displayName: "Level",
                                   minValue: -60, maxValue: 6, defaultValue: 0, unit: .decibels)
        case .slider:
            return ControlMetadata(parameterID: "mix", displayName: "Mix",
                                   minValue: 0, maxValue: 100, defaultValue: 50, unit: .percent)
        case .meter:
            return ControlMetadata(parameterID: "output", displayName: "Output",
                                   minValue: -60, maxValue: 0, defaultValue: -60, unit: .decibels)
        case .toggle:
            return ControlMetadata(parameterID: "enabled", displayName: "Enabled",
                                   minValue: 0, maxValue: 1, defaultValue: 1, unit: .generic,
                                   isContinuous: false, stepCount: 2)
        case .button:
            return ControlMetadata(parameterID: "trigger", displayName: "Trigger",
                                   minValue: 0, maxValue: 1, defaultValue: 0, unit: .generic,
                                   isContinuous: false, stepCount: 2,
                                   behaviourType: ControlBehaviourType.buttonPress.rawValue,
                                   interactionMode: ControlInteractionMode.press.rawValue)
        case .control:
            return ControlMetadata(parameterID: "value", displayName: "Value",
                                   minValue: 0, maxValue: 1, defaultValue: 0.5, unit: .generic,
                                   behaviourType: ControlBehaviourType.horizontalSlider.rawValue,
                                   interactionMode: ControlInteractionMode.linearDrag.rawValue)
        default:
            return nil
        }
    }

    private func defaultText(for kind: LayerKind) -> String? {
        switch kind {
        case .button: return "Button"
        case .label: return "Label"
        case .text: return "Text"
        case .toggle: return "Toggle"
        default: return nil
        }
    }
}

extension Document {
    /// A small starter document so the canvas isn't empty on first launch.
    static var sample: Document {
        let title = Layer(name: "Title", kind: .label,
                          frame: VRect(x: 24, y: 24, width: 220, height: 28),
                          style: LayerStyle(foregroundColor: .white, fontSize: 22, fontWeight: .bold),
                          text: "Synth Panel")
        let knob = Layer(name: "Cutoff Knob", kind: .knob,
                         frame: VRect(x: 24, y: 80, width: 80, height: 80),
                         style: LayerStyle(backgroundColor: VColor(hex: "#3A3A3C"), cornerRadius: 40))
        let slider = Layer(name: "Volume", kind: .slider,
                           frame: VRect(x: 130, y: 110, width: 200, height: 28))
        let play = Layer(name: "Play", kind: .button,
                         frame: VRect(x: 130, y: 160, width: 120, height: 44),
                         style: LayerStyle(backgroundColor: VColor(hex: "#0A84FF"),
                                           foregroundColor: .white, cornerRadius: 8,
                                           fontSize: 15, fontWeight: .semibold),
                         text: "Play")
        let panel = Layer(name: "Main Panel", kind: .panel,
                          frame: VRect(x: 40, y: 40, width: 380, height: 240),
                          style: LayerStyle(backgroundColor: VColor(hex: "#1C1C1E"), cornerRadius: 16),
                          children: [title, knob, slider, play])
        return Document(name: "Demo", roots: [panel], activeDevice: .mac)
    }
}
