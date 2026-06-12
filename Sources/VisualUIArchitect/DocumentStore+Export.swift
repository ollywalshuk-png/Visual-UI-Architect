import Foundation
import VUACore
import ExportIntegrityEngine

/// Runs the Export Integrity Pipeline against the current document.
extension DocumentStore {

    /// Exports the current document to `destination`. Returns the result so the
    /// UI can display assets, parameters, diagnostics, and build status.
    func exportPackage(
        to destination: URL,
        moduleName: String = "GeneratedUI",
        includeControls: Bool = true,
        includeMultiTargetSources: Bool = false
    ) -> Result<ExportResult, Error> {
        let request = ExportRequest(
            destination: destination,
            targetKind: .swiftPackage,
            moduleName: moduleName,
            viewName: "GeneratedView",
            includeControlsLibrary: includeControls,
            additionalCodeGenTargets: includeMultiTargetSources ? Self.multiTargetExportTargets : [])
        do {
            let result = try ExportIntegrityPipeline().export(document: document, request: request)
            repositoryStatus = result.hasErrors
                ? "Export completed with \(result.diagnostics.filter { $0.severity == .error }.count) error(s)."
                : "Exported to \(destination.lastPathComponent)."
            return .success(result)
        } catch {
            repositoryStatus = "Export failed: \(error)"
            return .failure(error)
        }
    }

    private static let multiTargetExportTargets: [CodeGenTarget] = [
        .react, .reactNative, .htmlCSS, .electronRenderer, .flutter, .uiKit, .appKit
    ]
}
