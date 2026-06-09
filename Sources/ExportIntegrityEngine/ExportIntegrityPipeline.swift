import Foundation
import VUACore
import CodeGenEngine

/// Orchestrates a complete, portable export:
///
///   generate SwiftUI → scan it → plan assets + params → copy files →
///   (optionally) copy VUAControls sources as a local module → write
///   manifests + report → return diagnostics.
///
/// Local-first: writes only inside `request.destination`. No network.
public struct ExportIntegrityPipeline: Sendable {
    public init() {}

    public func export(document: Document, request: ExportRequest) throws -> ExportResult {
        let fm = FileManager.default
        let dest = request.destination
        // 0. Destination check.
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        guard fm.isWritableFile(atPath: dest.path) else {
            throw ExportError.destinationNotWritable(dest)
        }

        // 1. Generate the SwiftUI source using the existing pipeline. Skip the
        // `#Preview` macro: it needs Xcode's PreviewsMacros plugin and would
        // fail `swift build` in CLT-only target environments.
        let generator = SwiftUIGenerator(viewName: request.viewName, includePreview: false)
        let generated: GeneratedSource
        do { generated = try generator.generate(document: document) }
        catch { throw ExportError.codeGenerationFailed("\(error)") }

        var diagnostics: [ExportDiagnostic] = []

        // 2. Plan assets and parameters from real generated source.
        let assetsDir = assetsDirectory(for: document, request: request)
        let assetPlan = AssetPlanner.plan(
            generatedSource: generated.contents,
            document: document,
            assetsDirectory: assetsDir)
        let paramPlan = ParameterPlanner.plan(document: document)
        diagnostics.append(contentsOf: assetPlan.diagnostics)
        diagnostics.append(contentsOf: paramPlan.diagnostics)

        // 3. Imports integrity. Generated code may only import what we ship.
        let imports = Set(GeneratedCodeScanner.imports(in: generated.contents))
        let satisfiable: Set<String> = ["SwiftUI", "Foundation",
                                        request.includeControlsLibrary ? "VUAControls" : ""]
            .filter { !$0.isEmpty }
            .reduce(into: Set<String>()) { $0.insert($1) }
        for imp in imports where !satisfiable.contains(imp) {
            diagnostics.append(ExportDiagnostic(
                severity: .error, code: .unavailableImport,
                message: "Generated code imports '\(imp)' which the export cannot satisfy.",
                detail: "Enable the matching library or remove the import."))
        }
        if GeneratedCodeScanner.usesControlsLibrary(in: generated.contents),
           !request.includeControlsLibrary {
            diagnostics.append(ExportDiagnostic(
                severity: .error, code: .missingControlsLibrary,
                message: "Generated code uses VUAControls but the export does not include it.",
                detail: "Enable 'Include controls library' in the export panel."))
        }

        // 4. Layout the destination and write code, assets, controls, manifests.
        let layout = DestinationLayout(request: request, root: dest)
        try fm.createDirectory(at: layout.sourcesDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: layout.resourcesDir, withIntermediateDirectories: true)

        // Generated view.
        let codePath = layout.sourcesDir.appendingPathComponent(generated.fileName)
        try write(generated.contents, to: codePath)

        // Asset files (skip ones flagged as errors / missing sources).
        for asset in assetPlan.assets {
            guard let src = asset.sourceURL, fm.fileExists(atPath: src.path) else { continue }
            let dst = layout.resourcesDir.appendingPathComponent(asset.exportedFileName)
            try? fm.removeItem(at: dst)
            do { try fm.copyItem(at: src, to: dst) }
            catch { throw ExportError.writeFailed(dst, error.localizedDescription) }
        }

        // VUAControls sources.
        var includedControls = false
        if request.includeControlsLibrary {
            includedControls = try copyControlsLibrary(into: layout.controlsDir)
            if !includedControls {
                diagnostics.append(ExportDiagnostic(
                    severity: .warning, code: .missingControlsLibrary,
                    message: "VUAControls sources are not bundled with this build of Visual UI Architect.",
                    detail: "Manually add VUAControls to the target. See the export report for instructions."))
            }
        }

        // SwiftPM `Package.swift` so the export is target-buildable as-is.
        if request.targetKind == .swiftPackage {
            let pkg = makePackageManifest(request: request, includedControls: includedControls)
            try write(pkg, to: dest.appendingPathComponent("Package.swift"))
        }

        // Manifests.
        let nowISO = ISO8601DateFormatter().string(from: Date())
        let assetManifest = AssetManifest(
            assets: assetPlan.assets, generatedAt: nowISO,
            schemaVersion: AssetManifest.currentSchemaVersion)
        let parameterManifest = ParameterManifest(
            parameters: paramPlan.parameters, generatedAt: nowISO,
            schemaVersion: ParameterManifest.currentSchemaVersion)
        let assetManifestPath = layout.manifestsDir.appendingPathComponent("assets.json")
        let parameterManifestPath = layout.manifestsDir.appendingPathComponent("parameters.json")
        try fm.createDirectory(at: layout.manifestsDir, withIntermediateDirectories: true)
        try writeJSON(assetManifest, to: assetManifestPath)
        try writeJSON(parameterManifest, to: parameterManifestPath)

        // Human-readable export report.
        let reportPath = dest.appendingPathComponent("EXPORT_REPORT.md")
        try write(reportText(
            request: request, includedControls: includedControls,
            assetPlan: assetPlan, paramPlan: paramPlan, diagnostics: diagnostics),
            to: reportPath)

        return ExportResult(
            destination: dest,
            generatedCodePath: codePath,
            assetManifestPath: assetManifestPath,
            parameterManifestPath: parameterManifestPath,
            reportPath: reportPath,
            assets: assetPlan.assets,
            parameters: paramPlan.parameters,
            includedControlsLibrary: includedControls,
            diagnostics: diagnostics)
    }

    // MARK: - Helpers

    /// Where imported assets live in the source document — passed in by the
    /// caller (the app) when the document was loaded from a repo, otherwise
    /// falls back to the user's Application Support directory.
    private func assetsDirectory(for document: Document, request: ExportRequest) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("VisualUIArchitect/Assets")
    }

    /// Copies the bundled VUAControls source files into `dir`. Returns true on
    /// success, false when the resource bundle isn't available (e.g. in a
    /// stripped CLI build).
    private func copyControlsLibrary(into dir: URL) throws -> Bool {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // Source bundle: VUAControlsSources resource folder.
        guard let bundleURL = Bundle.module.url(forResource: "VUAControlsSources", withExtension: nil) else {
            return false
        }
        let contents = try fm.contentsOfDirectory(at: bundleURL, includingPropertiesForKeys: nil)
        for src in contents where src.pathExtension == "swift" {
            let dst = dir.appendingPathComponent(src.lastPathComponent)
            try? fm.removeItem(at: dst)
            try fm.copyItem(at: src, to: dst)
        }
        return true
    }

    private func write(_ string: String, to url: URL) throws {
        do { try string.write(to: url, atomically: true, encoding: .utf8) }
        catch { throw ExportError.writeFailed(url, error.localizedDescription) }
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw ExportError.writeFailed(url, error.localizedDescription)
        }
    }

    private func makePackageManifest(request: ExportRequest, includedControls: Bool) -> String {
        var targetDeps: [String] = []
        if includedControls {
            targetDeps.append("\"VUAControls\"")
        }
        let depsArray = targetDeps.isEmpty ? "[]" : "[\(targetDeps.joined(separator: ", "))]"
        let controlsTarget = includedControls ? """
                .target(
                    name: "VUAControls",
                    path: "Sources/VUAControls"),
        """ : ""
        return """
        // swift-tools-version: 6.0
        // Generated by Visual UI Architect — Phase 5 export integrity.
        import PackageDescription

        let package = Package(
            name: "\(request.moduleName)",
            platforms: [.macOS(.v14), .iOS(.v17)],
            products: [
                .library(name: "\(request.moduleName)", targets: ["\(request.moduleName)"])\(includedControls ? ",\n        .library(name: \"VUAControls\", targets: [\"VUAControls\"])" : "")
            ],
            targets: [
        \(controlsTarget)
                .target(
                    name: "\(request.moduleName)",
                    dependencies: \(depsArray),
                    path: "Sources/\(request.moduleName)",
                    resources: [.process("Resources")])
            ]
        )
        """
    }

    private func reportText(
        request: ExportRequest, includedControls: Bool,
        assetPlan: AssetPlanner.Plan, paramPlan: ParameterPlanner.Plan,
        diagnostics: [ExportDiagnostic]
    ) -> String {
        var lines: [String] = []
        lines.append("# Export Report — \(request.moduleName)")
        lines.append("")
        lines.append("- Target: **\(request.targetKind.rawValue)**")
        lines.append("- View: **\(request.viewName)**")
        lines.append("- VUAControls included: **\(includedControls ? "yes" : "no")**")
        lines.append("")
        lines.append("## Assets (\(assetPlan.assets.count))")
        for a in assetPlan.assets {
            let mark = a.sourceURL != nil ? "✓" : "✗"
            lines.append("- \(mark) `\(a.imageName)` → `Resources/\(a.exportedFileName)`")
        }
        lines.append("")
        lines.append("## Parameters (\(paramPlan.parameters.count))")
        for p in paramPlan.parameters {
            let mark = p.isPlaceholder ? "⚠︎" : "•"
            lines.append("- \(mark) `\(p.parameterID)` (\(p.displayName)) " +
                         "\(String(format: "%.2f", p.minValue))…\(String(format: "%.2f", p.maxValue)) \(p.unit)")
        }
        lines.append("")
        lines.append("## Diagnostics")
        if diagnostics.isEmpty {
            lines.append("- _No issues._")
        } else {
            for d in diagnostics {
                lines.append("- **\(d.severity.rawValue.uppercased())** [\(d.code.rawValue)] \(d.message)")
                if let detail = d.detail { lines.append("  - \(detail)") }
            }
        }
        if !includedControls {
            lines.append("")
            lines.append("## Manual VUAControls setup")
            lines.append("Add the `VUAControls` library as a local SwiftPM dependency or copy")
            lines.append("its sources from Visual UI Architect's `Sources/VUAControls/`.")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Where things live inside the export root.
struct DestinationLayout {
    let request: ExportRequest
    let root: URL

    var sourcesDir: URL { root.appendingPathComponent("Sources/\(request.moduleName)") }
    var resourcesDir: URL { sourcesDir.appendingPathComponent("Resources") }
    var controlsDir: URL { root.appendingPathComponent("Sources/VUAControls") }
    var manifestsDir: URL { root.appendingPathComponent("Manifests") }
}
