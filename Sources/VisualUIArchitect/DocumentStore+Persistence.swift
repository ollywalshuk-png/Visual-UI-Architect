import Foundation
import AppKit
import UniformTypeIdentifiers
import VUACore
import PersistenceEngine

/// Save/open/recent operations on top of `PersistenceEngine`. All disk I/O is
/// local-first and routed through `VUABundle`.
extension DocumentStore {

    // Shared recents + recovery stores.
    static let recents = RecentDocumentsStore()
    static let recovery = RecoveryStore()

    /// Source directory the writer should pull asset files from. When the
    /// document is already saved (and assets live inside the bundle) the
    /// bundle's own `Assets/` directory is used so writes are no-ops.
    private var currentAssetsSource: URL {
        assetsDirectory
    }

    // MARK: - Save

    /// Save to the existing document URL, or fall back to Save As when the
    /// document has never been saved.
    @discardableResult
    func save() -> Bool {
        guard let url = documentURL else { return saveAs() }
        return write(to: url)
    }

    /// Prompts the user for a destination and saves there.
    @discardableResult
    func saveAs() -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: VUABundle.fileExtension) ?? .data]
        panel.nameFieldStringValue = (document.name.isEmpty ? "Untitled" : document.name)
            + "." + VUABundle.fileExtension
        panel.canCreateDirectories = true
        panel.title = "Save Project"
        guard panel.runModal() == .OK, var url = panel.url else { return false }
        if url.pathExtension != VUABundle.fileExtension {
            url = url.appendingPathExtension(VUABundle.fileExtension)
        }
        return write(to: url)
    }

    private func write(to url: URL) -> Bool {
        do {
            // Copy assets from wherever they currently live INTO the new bundle.
            // After this call, the bundle is the canonical source for everything.
            let source = currentAssetsSource
            _ = try VUABundle.write(document, to: url, copyingAssetsFrom: source)
            documentURL = url
            markClean()
            Self.recents.record(url)
            // Drop a version snapshot and clear the (now-redundant) recovery file.
            _ = try? SnapshotStore.write(document, into: url)
            Self.recovery.clear()
            repositoryStatus = "Saved \(url.lastPathComponent)."
            return true
        } catch {
            repositoryStatus = "Save failed: \(error)"
            return false
        }
    }

    // MARK: - Autosave & crash recovery

    /// Starts a repeating autosave that writes the live document to the recovery
    /// file whenever it's dirty. Safe to call once at launch.
    func startAutosave(interval: TimeInterval = 30) {
        autosaveTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.autosaveTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        autosaveTimer = timer
    }

    private func autosaveTick() {
        guard isDirty else { return }
        try? Self.recovery.write(document, originalPath: documentURL?.path)
    }

    /// A recovery payload from a previous unclean session, if any.
    func pendingRecovery() -> RecoveryStore.Recovered? {
        Self.recovery.hasRecovery ? Self.recovery.load() : nil
    }

    /// Restores a recovered document into the editor. Keeps it dirty so the
    /// user is nudged to save it to a real bundle.
    func restoreRecovery(_ recovered: RecoveryStore.Recovered) {
        let url = recovered.meta.originalPath.map { URL(fileURLWithPath: $0) }
        loadDocument(recovered.document, fromURL: url)
        markDirty()
        repositoryStatus = "Recovered unsaved work from \(recovered.meta.documentName)."
    }

    func discardRecovery() { Self.recovery.clear() }

    // MARK: - Snapshots

    func snapshots() -> [SnapshotStore.Info] {
        guard let url = documentURL else { return [] }
        return SnapshotStore.list(in: url)
    }

    func restoreSnapshot(_ info: SnapshotStore.Info) {
        guard let doc = try? SnapshotStore.read(info.url) else {
            repositoryStatus = "Could not read snapshot."
            return
        }
        // Restore into the current document but keep the same backing URL.
        let url = documentURL
        loadDocument(doc, fromURL: url)
        markDirty()
        repositoryStatus = "Restored snapshot \(info.fileName)."
    }

    // MARK: - Close handling

    /// True when closing would lose unsaved work.
    var needsSaveBeforeClose: Bool { isDirty }

    /// Requests a window close. If there are unsaved changes, raises the
    /// save-before-close prompt; otherwise closes immediately.
    func requestClose() {
        if needsSaveBeforeClose {
            closeConfirmPending = true
        } else {
            performClose()
        }
    }

    /// Performs the actual window close (after the user resolves the prompt).
    func performClose() {
        autosaveTimer?.invalidate()
        Self.recovery.clear()
        NSApplication.shared.keyWindow?.performClose(nil)
    }

    // MARK: - Open

    /// Prompts for a `.vuaproj` bundle and loads it (guarding unsaved work).
    func openProject() {
        if needsSaveBeforeClose { pendingDirtyAction = .openPanel; return }
        presentOpenPanel()
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: VUABundle.fileExtension) ?? .data]
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.title = "Open Project"
        if panel.runModal() == .OK, let url = panel.url {
            performOpen(url)
        }
    }

    /// Loads a bundle, guarding unsaved work (used by Open Recent / panel).
    func openProject(at url: URL) {
        if needsSaveBeforeClose { pendingDirtyAction = .open(url); return }
        performOpen(url)
    }

    private func performOpen(_ url: URL) {
        // Corrupted-document diagnostics before load.
        if let problem = VUABundle.diagnose(url) {
            repositoryStatus = "Can't open \(url.lastPathComponent): \(problem)"
            return
        }
        // Two-window guard: warn (status) if this doc is already open elsewhere.
        if OpenDocumentRegistry.shared.isOpen(url) {
            repositoryStatus = "Note: \(url.lastPathComponent) is already open in another window."
        }
        do {
            let loaded = try VUABundle.read(from: url)
            if let previous = documentURL { OpenDocumentRegistry.shared.unregister(previous) }
            loadDocument(loaded, fromURL: url)
            OpenDocumentRegistry.shared.register(url)
            Self.recents.record(url)
            repositoryStatus = "Opened \(url.lastPathComponent)."
        } catch {
            repositoryStatus = "Open failed: \(error)"
        }
    }

    // MARK: - New

    /// Starts a fresh untitled document (guarding unsaved work).
    func newDocument() {
        if needsSaveBeforeClose { pendingDirtyAction = .newDocument; return }
        performNew()
    }

    private func performNew() {
        if let previous = documentURL { OpenDocumentRegistry.shared.unregister(previous) }
        loadDocument(.sample, fromURL: nil)
        repositoryStatus = "New document."
    }

    /// Resolves a deferred open/new after the user answers the save prompt.
    /// `save == true` saves first, `false` discards, `nil` cancels.
    func resolvePendingDirtyAction(save: Bool?) {
        guard let action = pendingDirtyAction else { return }
        pendingDirtyAction = nil
        switch save {
        case .some(true): if !self.save() { return }
        case .some(false): markClean()
        case .none: return
        }
        switch action {
        case .openPanel: presentOpenPanel()
        case .open(let url): performOpen(url)
        case .newDocument: performNew()
        }
    }

    /// Auto-reopen on launch — loads the most recently saved bundle that still
    /// exists. Silently does nothing if there is no recent.
    func autoReopenLast() {
        guard let url = Self.recents.mostRecentExisting() else { return }
        openProject(at: url)
    }

    // MARK: - Window title

    /// Title bar string reflecting name, file name, and dirty state.
    var windowTitle: String {
        let base: String
        if let url = documentURL {
            base = url.deletingPathExtension().lastPathComponent
        } else if let opened = openedFileName {
            base = "\(document.name) — \(opened)"
        } else {
            base = document.name
        }
        return isDirty ? "\(base) — Edited" : base
    }
}
