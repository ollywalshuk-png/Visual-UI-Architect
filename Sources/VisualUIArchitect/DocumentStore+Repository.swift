import Foundation
import SwiftUI
import VUACore
import RepositoryEngine

/// Repository round-trip features layered onto the document store: opening
/// existing SwiftUI sources into the canvas, watching for external edits, and
/// applying visual changes back to source through the safe-apply pipeline.
extension DocumentStore {

    // MARK: - Opening sources

    /// Opens a single SwiftUI file, replacing the canvas with its parsed layers.
    func openSwiftUIFile(at url: URL) {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            repositoryStatus = "Could not read \(url.lastPathComponent)."
            return
        }
        // Bindings store the absolute path so apply-to-source can resolve it
        // even without a repository root.
        let views = SwiftUIParser().parse(source: source, filePath: url.path)
        guard let view = views.first else {
            repositoryStatus = "No SwiftUI View found in \(url.lastPathComponent)."
            return
        }
        loadParsedView(view, sourceURL: url)
        if repositoryRoot == nil { repositoryRoot = url.deletingLastPathComponent() }
        watch(url: url)
        repositoryStatus = "Opened \(view.typeName) from \(url.lastPathComponent)."
    }

    /// Opens a repository directory and scans it for views and assets.
    func openRepository(at url: URL) {
        repositoryRoot = url
        repositoryFiles = RepositoryScanner(root: url).scan()
        repositoryStatus = "Scanned \(repositoryFiles.count) files in \(url.lastPathComponent)."
    }

    /// Opens a repository file (resolved against the repository root).
    func openRepositoryFile(_ file: RepositoryFile) {
        openSwiftUIFile(at: URL(fileURLWithPath: file.absolutePath))
    }

    private func loadParsedView(_ view: ParsedView, sourceURL: URL) {
        openedFileName = sourceURL.lastPathComponent
        mutate { doc in
            doc.name = view.typeName
            doc.roots = view.roots
        }
        selection = []
    }

    // MARK: - External-change watching

    private func watch(url: URL) {
        fileWatcher?.stop()
        let watcher = FileWatcher(url: url) { [weak self] in
            Task { @MainActor in self?.handleExternalChange(at: url) }
        }
        watcher.start()
        fileWatcher = watcher
    }

    private func handleExternalChange(at url: URL) {
        guard !isInteracting else { return }   // don't clobber an in-progress edit
        guard let source = try? String(contentsOf: url, encoding: .utf8),
              let view = SwiftUIParser().parse(source: source, filePath: url.path).first else { return }
        mutate { doc in doc.roots = view.roots }
        repositoryStatus = "Refreshed from external edit to \(url.lastPathComponent)."
    }

    // MARK: - Apply to source

    func previewApplyToSource() -> SafeApplyResult? {
        guard let root = repositoryRoot else {
            repositoryStatus = "Open a file or repository first."
            return nil
        }
        guard ensureSafeToWrite() else { return nil }
        if importedSourceChangedExternally {
            repositoryStatus = "Preview blocked: \(openedFileName ?? "the source file") changed on disk since import. Re-import before applying."
            return nil
        }
        if importedSourcePath != nil && importedSourceHasAnchors == false {
            repositoryStatus = "Preview blocked: this UI was imported as editable temporary layers because the source has no anchors."
            return nil
        }
        do {
            let result = try SafeApplyPipeline().preview(document: document, repoRoot: root)
            repositoryStatus = result.diff.isEmpty
                ? "Preview found no source changes."
                : "Preview ready: \(result.plannedChanges.count) anchored change(s)."
            return result
        } catch {
            repositoryStatus = "Preview failed: \(error)"
            return nil
        }
    }

    /// Writes the current bound-layer geometry back to source via the
    /// safe-apply pipeline (validate → write → build → diff).
    func applyToSource(runBuild: Bool) -> SafeApplyResult? {
        guard let root = repositoryRoot else {
            repositoryStatus = "Open a file or repository first."
            return nil
        }
        // Phase 10: refresh workspace safety and block writes to a generated
        // export / build / dependency folder or a repo mid-merge/rebase.
        guard ensureSafeToWrite() else { return nil }
        // Phase 18: if this document was imported from existing source, block
        // when that file changed on disk since import (avoid clobbering edits).
        if importedSourceChangedExternally {
            repositoryStatus = "Blocked: \(openedFileName ?? "the source file") changed on disk since import. Re-import before applying."
            return nil
        }
        if importedSourcePath != nil && importedSourceHasAnchors == false {
            repositoryStatus = "Apply blocked: this UI was imported as editable temporary layers because the source has no anchors. Add accessibilityIdentifier anchors in source, then re-import."
            return nil
        }
        do {
            let result = try SafeApplyPipeline().apply(document: document, repoRoot: root, runBuild: runBuild)
            switch result.blockedAt {
            case .validate: repositoryStatus = "Blocked: fix \(result.validation.errorCount) validation error(s) first."
            case .build: repositoryStatus = "Blocked: build failed after writing."
            case .some(let s): repositoryStatus = "Blocked at \(s.rawValue)."
            case nil:
                repositoryStatus = result.filesWritten.isEmpty
                    ? "No changes to apply."
                    : "Applied to \(result.filesWritten.count) file(s)."
                // Keep the import hash in sync with what we just wrote so the
                // next apply isn't falsely blocked as "changed externally".
                if !result.filesWritten.isEmpty { refreshImportedSourceHash() }
            }
            return result
        } catch {
            repositoryStatus = "Apply failed: \(error)"
            return nil
        }
    }
}
