import Foundation
import BuildIntelligenceEngine

/// Build-intelligence integration: resolve and cache a `BuildContext` for the
/// open repository so build state is visible and failures are explainable.
extension DocumentStore {

    /// Resolves the build context for a directory (defaults to the open repo
    /// root), caches it on the store, and returns it.
    @discardableResult
    func refreshBuildContext(at url: URL? = nil, kind: BuildKind = .localDevelopment) -> BuildContext? {
        guard let root = url ?? repositoryRoot else {
            buildContext = nil
            return nil
        }
        let ctx = BuildInspector().makeContext(root: root, kind: kind)
        buildContext = ctx
        return ctx
    }

    /// Human explanation for the most recent failed build output, if the
    /// engine recognises the failure pattern.
    nonisolated func explainBuildFailure(_ output: String) -> String? {
        BuildInspector.explainFailure(output)
    }
}
