import Foundation
import VUACore

/// What kind of target project we're exporting into. Drives where assets land
/// and whether to emit setup instructions or write files directly.
public enum ExportTargetKind: String, Codable, Hashable, Sendable {
    /// A SwiftPM package — `Sources/<module>/` for code, `Resources/` for assets.
    case swiftPackage
    /// An Xcode app — assets land in `Assets.xcassets/`, code in the chosen folder.
    case xcodeApp
}

/// User-supplied export request. Local-first: a single writable directory.
public struct ExportRequest: Sendable {
    public var destination: URL
    public var targetKind: ExportTargetKind
    /// Module name for the SwiftPM target (or folder name for an Xcode app).
    public var moduleName: String
    /// Generated SwiftUI view type name (matches the codegen's `viewName`).
    public var viewName: String
    /// When true, `VUAControls` sources are copied into the export as a local module.
    public var includeControlsLibrary: Bool
    /// Additional implemented codegen targets to emit beside the buildable SwiftUI package.
    public var additionalCodeGenTargets: [CodeGenTarget]

    public init(
        destination: URL,
        targetKind: ExportTargetKind = .swiftPackage,
        moduleName: String = "GeneratedUI",
        viewName: String = "GeneratedView",
        includeControlsLibrary: Bool = true,
        additionalCodeGenTargets: [CodeGenTarget] = []
    ) {
        self.destination = destination
        self.targetKind = targetKind
        self.moduleName = moduleName
        self.viewName = viewName
        self.includeControlsLibrary = includeControlsLibrary
        self.additionalCodeGenTargets = additionalCodeGenTargets
    }
}

/// One asset that needs to ship with the export.
public struct ExportedAsset: Hashable, Sendable, Codable {
    /// The `Image("name")` literal as it appears in generated code.
    public var imageName: String
    /// Sanitised filename written into the export.
    public var exportedFileName: String
    /// Source asset id from the document.
    public var sourceAssetID: UUID?
    /// Absolute source URL (where the imported file lives in our assets dir).
    public var sourceURL: URL?
    public var format: Asset.Format?
}

/// Asset manifest written next to the exported code.
public struct AssetManifest: Codable, Sendable {
    public var assets: [ExportedAsset]
    public var generatedAt: String
    public var schemaVersion: Int

    public static let currentSchemaVersion = 1
}

/// Single AU/plugin parameter entry, derived from `ControlMetadata`.
public struct ParameterEntry: Codable, Sendable, Hashable {
    public var layerID: UUID
    public var parameterID: String
    public var displayName: String
    public var minValue: Double
    public var maxValue: Double
    public var defaultValue: Double
    public var unit: String
    public var isContinuous: Bool
    public var stepCount: Int?
    /// MIDI CC number (0...127) if assigned. Reserved for future binding work.
    public var midiCC: Int?
    /// Automation flag (host-exposed). Reserved for future binding work.
    public var automationEnabled: Bool
    /// True when metadata looks like a default placeholder the user hasn't reviewed.
    public var isPlaceholder: Bool
}

public struct ParameterManifest: Codable, Sendable {
    public var parameters: [ParameterEntry]
    public var generatedAt: String
    public var schemaVersion: Int
    public static let currentSchemaVersion = 1
}

/// Single diagnostic produced during export. All failures are surfaced; no
/// silent skips.
public struct ExportDiagnostic: Hashable, Sendable, Codable {
    public enum Severity: String, Codable, Sendable { case info, warning, error }
    public enum Code: String, Codable, Sendable {
        case missingAssetFile          // Image("…") has no resolvable source
        case unresolvedAssetReference  // generated code references an unknown name
        case duplicateAssetName        // two assets map to the same filename
        case unsupportedAssetFormat
        case unsafeFilename            // sanitised to a safe variant
        case missingControlsLibrary    // generated code needs it; export omits it
        case unsafeDestination         // destination not writable / missing
        case placeholderParameter      // ControlMetadata looks unreviewed
        case controlNotProductionBound // visual control with no binding/anchor
        case unavailableImport         // generated code imports a module we can't satisfy
        case unsupportedCodegenTarget  // requested secondary target has no generator
    }

    public var severity: Severity
    public var code: Code
    public var message: String
    public var detail: String?
}

/// One generated source file emitted for a secondary framework target.
public struct ExportedCodeFile: Hashable, Sendable {
    public var target: CodeGenTarget
    public var fileName: String
    public var path: URL
    public var relativePath: String
}

/// Result of running the pipeline. Mirrors the brief's success criteria:
/// generated code + assets + controls + manifest + report + validation.
public struct ExportResult: Sendable {
    public var destination: URL
    public var generatedCodePath: URL
    public var additionalCodeFiles: [ExportedCodeFile]
    public var assetManifestPath: URL
    public var parameterManifestPath: URL
    public var reportPath: URL
    public var assets: [ExportedAsset]
    public var parameters: [ParameterEntry]
    public var includedControlsLibrary: Bool
    public var diagnostics: [ExportDiagnostic]

    public var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }
}

/// Errors that abort export before producing any partial state.
public enum ExportError: Error, CustomStringConvertible {
    case destinationNotWritable(URL)
    case codeGenerationFailed(String)
    case writeFailed(URL, String)

    public var description: String {
        switch self {
        case .destinationNotWritable(let url): return "Export destination not writable: \(url.path)"
        case .codeGenerationFailed(let reason): return "Code generation failed: \(reason)"
        case .writeFailed(let url, let reason): return "Failed to write \(url.lastPathComponent): \(reason)"
        }
    }
}
