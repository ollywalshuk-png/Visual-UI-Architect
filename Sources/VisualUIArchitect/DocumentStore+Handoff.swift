import Foundation
import HandoffGeneratorEngine

/// Handoff generation: snapshot the live app/repo/document state into a
/// deterministic `HandoffInput` and render HANDOFF.md.
extension DocumentStore {

    /// The package's module map — kept in code so a handoff never lists
    /// modules that don't exist in this build.
    static let handoffModules: [String] = [
        "VUACore", "LayerEngine", "CanvasEngine", "AssetEngine", "LayoutEngine",
        "ConstraintEngine", "ValidationEngine", "GitEngine", "CodeGenEngine",
        "AIEngine", "PreviewEngine", "RepositoryEngine", "ExportIntegrityEngine",
        "PersistenceEngine", "PresetEngine", "WorkspaceEngine",
        "BuildIntelligenceEngine", "HandoffGeneratorEngine",
        "VUAControls", "VisualUIArchitect", "VUACheck",
    ]

    static let handoffCapabilities: [String] = [
        "Visual canvas editing: shapes, gradients, masks, groups, multi-select, clipboard, z-order",
        "Canvas workflow: zoom/fit/100%, grid + snap, rulers, guides, alignment guides",
        "Asset pipeline: import/browse/drag-drop/replace/write-back, bundle-relative resolution",
        "Plugin controls (knob/fader/meter/…) with AU parameter metadata",
        "SwiftUI code generation with stable accessibility anchors",
        "Repository round-trip: SwiftSyntax parse → visual edit → source-fidelity write-back",
        "Safe-apply pipeline: validate → preflight → write → build → diff",
        "Export integrity: self-contained buildable SwiftPM package + manifests + report",
        ".vuaproj persistence with autosave, crash recovery, and version snapshots",
        "Workspace safety: wrong-repo/nested-repo/generated-export/dirty-tree detection",
        "Build intelligence: toolchain/lockfile diagnostics + failure explanations",
        "Hardening: duplicate anchors/IDs/assets, off-canvas, source preflight (hash, conflicts)",
    ]

    /// Builds the live snapshot used by the generator.
    func makeHandoffInput() -> HandoffInput {
        let ctx = refreshWorkspace()
        var warnings = ctx?.warnings.map(\.message) ?? []
        if validation.hasErrors {
            warnings.append("Document has \(validation.errorCount) validation error(s).")
        }
        return HandoffInput(
            repoPath: repositoryRoot?.path,
            documentPath: documentURL?.path,
            branch: ctx?.branch,
            latestCommit: ctx?.latestCommit,
            workingTreeDirty: ctx?.isDirty,
            buildStatus: "run `swift build` to verify (state changes too fast to bake in)",
            checkResult: "run `swift run VUACheck` to verify",
            modules: Self.handoffModules,
            capabilities: Self.handoffCapabilities,
            documentName: document.name,
            layerCount: document.allLayers.count,
            assetCount: document.assets.count,
            targetDevice: document.activeDevice.name,
            warnings: warnings,
            knownLimitations: [
                "Traffic-light close button bypasses save-before-close (⌘W is guarded; autosave covers the gap).",
                "Round-trip write-back covers frames and image names; broader style/structure write-back is roadmap.",
            ],
            roadmap: ["See ROADMAP.md — the phase tracker is the single source of truth."],
            nextRecommendedPhase: "Open ROADMAP.md and take the first phase still marked ⬜ planned.",
            generatedAt: ISO8601DateFormatter().string(from: Date()))
    }

    /// Renders a handoff and returns it.
    func generateHandoff(mode: HandoffMode) -> String {
        HandoffGenerator().generate(makeHandoffInput(), mode: mode)
    }

    /// Writes HANDOFF.md into the repository root (or alongside the document
    /// when no repo is open). Returns the written URL, or nil on failure.
    @discardableResult
    func writeHandoff(mode: HandoffMode) -> URL? {
        let dir = repositoryRoot ?? documentURL?.deletingLastPathComponent()
        guard let dir else { return nil }
        let url = dir.appendingPathComponent("HANDOFF.md")
        do {
            try generateHandoff(mode: mode).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
