import Foundation
import WorkspaceEngine

/// Workspace-safety integration: resolve and cache a `WorkspaceContext`, and
/// gate source-writing operations on it.
extension DocumentStore {

    /// Resolves workspace safety for a directory (defaults to the open repo
    /// root), caches it on the store, and returns it.
    @discardableResult
    func refreshWorkspace(at url: URL? = nil) -> WorkspaceContext? {
        guard let root = url ?? repositoryRoot else {
            workspaceContext = nil
            return nil
        }
        let ctx = WorkspaceResolver().resolve(root)
        workspaceContext = ctx
        return ctx
    }

    /// True when the current workspace is safe to write source into. Refreshes
    /// first so the check is never stale. Sets `repositoryStatus` on block.
    func ensureSafeToWrite() -> Bool {
        guard let ctx = refreshWorkspace() else { return true } // no repo → caller handles
        if !ctx.isSafeToWrite {
            let reason = ctx.warnings.first(where: { $0.severity == .error })?.message
                ?? "The selected folder is not a safe source repository."
            repositoryStatus = "Blocked: \(reason)"
            return false
        }
        return true
    }
}
