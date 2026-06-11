import Foundation
import VUACore
import RepositoryEngine

/// Phase 18 — "Import Existing UI" store glue. Scans a file/repo for SwiftUI
/// view candidates, imports the chosen one into the canvas as editable layers,
/// and records provenance (source path + content hash + view name) so
/// Apply-to-Source can refuse to write over an externally-changed file.
extension DocumentStore {

    // MARK: - Scan

    func scanForImportCandidates(file url: URL) -> [ExistingUIImport.Candidate] {
        ExistingUIImport.candidates(inFile: url)
    }

    func scanForImportCandidates(repo root: URL) -> [ExistingUIImport.Candidate] {
        ExistingUIImport.scanRepository(root)
    }

    func detectProject(at root: URL) -> ExistingUIImport.ProjectInfo {
        ExistingUIImport.detectProject(root)
    }

    // MARK: - Import

    /// Imports a candidate into the canvas, recording provenance for round-trip.
    /// Returns true on success.
    @discardableResult
    func importExistingUI(_ candidate: ExistingUIImport.Candidate) -> Bool {
        guard let imported = ExistingUIImport.importCandidate(candidate) else {
            repositoryStatus = "Import failed: couldn't parse \(candidate.viewName)."
            return false
        }
        let url = URL(fileURLWithPath: candidate.filePath)

        // Replace the document with the imported view; mark dirty so the user
        // knows it's not yet saved as a .vuaproj.
        loadDocument(Document(name: imported.view.typeName, roots: imported.view.roots), fromURL: nil)
        markDirty()

        // Provenance + repository association (so it appears in the Repo tab and
        // Apply-to-Source targets the right root/file).
        openedFileName = url.lastPathComponent
        importedSourcePath = candidate.filePath
        importedSourceHash = imported.sourceHash
        importedViewName = imported.view.typeName
        if let repoRoot = candidate.repoRoot {
            repositoryRoot = URL(fileURLWithPath: repoRoot)
        } else {
            repositoryRoot = url.deletingLastPathComponent()
        }
        repositoryFiles = scanRepositoryFiles()

        if !imported.hasAnchors {
            repositoryStatus = "Imported \(imported.view.typeName). No anchors found — round-trip needs anchors."
        } else {
            repositoryStatus = "Imported \(imported.view.typeName) from \(url.lastPathComponent)."
        }
        return true
    }

    /// Re-scans the repository file list (Repository tab) for the current root.
    private func scanRepositoryFiles() -> [RepositoryFile] {
        guard let root = repositoryRoot else { return [] }
        return RepositoryScanner(root: root).scan()
    }

    // MARK: - Apply guard

    /// True when an imported source file changed on disk since import. Apply
    /// must block in this case to avoid clobbering external edits.
    var importedSourceChangedExternally: Bool {
        guard let path = importedSourcePath, let hash = importedSourceHash else { return false }
        return ExistingUIImport.sourceChanged(at: path, since: hash)
    }

    /// Refreshes the stored hash to the file's current contents (call after a
    /// successful apply so subsequent applies aren't falsely blocked).
    func refreshImportedSourceHash() {
        guard let path = importedSourcePath,
              let source = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else { return }
        importedSourceHash = ExistingUIImport.sourceHash(source)
    }
}
