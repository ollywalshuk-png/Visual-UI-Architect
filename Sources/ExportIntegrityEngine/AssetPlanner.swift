import Foundation
import VUACore
import AssetEngine

/// Plans which asset files to copy into an export, sanitises filenames, and
/// produces diagnostics for missing/duplicate/unsupported references.
public enum AssetPlanner {

    public struct Plan: Sendable {
        public var assets: [ExportedAsset]
        public var diagnostics: [ExportDiagnostic]
    }

    /// Drive: scan generated source for image names, match each to a document
    /// asset, sanitise the destination filename, and report what's missing.
    public static func plan(
        generatedSource: String,
        document: Document,
        assetsDirectory: URL
    ) -> Plan {
        let references = GeneratedCodeScanner.imageReferences(in: generatedSource)
        var assets: [ExportedAsset] = []
        var diagnostics: [ExportDiagnostic] = []
        var seenFileNames: Set<String> = []

        // Document assets keyed by their (case-insensitive) name for matching.
        let assetsByName = Dictionary(grouping: document.assets, by: { $0.name.lowercased() })

        for reference in references {
            let match = assetsByName[reference.lowercased()]?.first
            let format = match?.format
            let safeName = sanitize(reference, extensionFallback: format?.rawValue ?? "png")
            if safeName != "\(reference).\(format?.rawValue ?? "png")" && safeName != reference {
                diagnostics.append(ExportDiagnostic(
                    severity: .info, code: .unsafeFilename,
                    message: "Renamed asset filename: '\(reference)' → '\(safeName)'.",
                    detail: nil))
            }
            if !seenFileNames.insert(safeName).inserted {
                diagnostics.append(ExportDiagnostic(
                    severity: .error, code: .duplicateAssetName,
                    message: "Duplicate exported asset filename: '\(safeName)'.",
                    detail: "Two image references resolve to the same file."))
            }

            guard let match else {
                diagnostics.append(ExportDiagnostic(
                    severity: .error, code: .unresolvedAssetReference,
                    message: "Image(\"\(reference)\") has no matching imported asset.",
                    detail: "Import the asset (it must keep the name '\(reference)') or remove the reference."))
                assets.append(ExportedAsset(
                    imageName: reference, exportedFileName: safeName,
                    sourceAssetID: nil, sourceURL: nil, format: nil))
                continue
            }

            let sourceURL = AssetLibrary.fileURL(for: match, in: assetsDirectory)
            if !FileManager.default.fileExists(atPath: sourceURL.path) {
                diagnostics.append(ExportDiagnostic(
                    severity: .error, code: .missingAssetFile,
                    message: "Asset '\(match.name)' file not found at \(sourceURL.path).",
                    detail: "Re-import the asset or restore the missing file."))
            }
            if Asset.Format(fileExtension: sourceURL.pathExtension) == nil {
                diagnostics.append(ExportDiagnostic(
                    severity: .error, code: .unsupportedAssetFormat,
                    message: "Asset '\(match.name)' has unsupported format '\(sourceURL.pathExtension)'.",
                    detail: nil))
            }
            assets.append(ExportedAsset(
                imageName: reference, exportedFileName: safeName,
                sourceAssetID: match.id, sourceURL: sourceURL, format: match.format))
        }
        return Plan(assets: assets, diagnostics: diagnostics)
    }

    /// Replace characters not safe for cross-platform filenames; ensure an
    /// extension is present so SwiftPM resource lookup is unambiguous.
    public static func sanitize(_ name: String, extensionFallback: String) -> String {
        // Strip path separators and control characters; collapse whitespace.
        let unsafe: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
        var stem = String(name.map { unsafe.contains($0) || $0.isNewline ? "_" : $0 })
        stem = stem.trimmingCharacters(in: .whitespaces)
        if stem.isEmpty { stem = "asset" }

        // If the original name already has a recognised extension, keep it.
        let nsName = stem as NSString
        let ext = nsName.pathExtension
        let stemNoExt = nsName.deletingPathExtension
        if Asset.Format(fileExtension: ext) != nil { return "\(stemNoExt).\(ext.lowercased())" }
        return "\(stem).\(extensionFallback.lowercased())"
    }
}
