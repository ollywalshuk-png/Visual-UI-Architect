import Foundation

/// The kind of build being performed or reasoned about. VUA is local-first,
/// but exports and target repos may be built by CI/staging/production
/// pipelines — the engine models all of them so build state is explainable.
public enum BuildKind: String, CaseIterable, Sendable, Codable, Identifiable {
    case localDevelopment
    case debug
    case release
    case ci
    case staging
    case production
    case exportValidation

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .localDevelopment: return "Local Development"
        case .debug: return "Debug"
        case .release: return "Release"
        case .ci: return "CI"
        case .staging: return "Staging"
        case .production: return "Production"
        case .exportValidation: return "Export Validation"
        }
    }

    /// The SwiftPM configuration this kind maps to.
    public var configuration: String {
        switch self {
        case .localDevelopment, .debug, .exportValidation, .ci: return "debug"
        case .release, .staging, .production: return "release"
        }
    }
}

/// One stage of the build lifecycle, mapped to this project's Swift pipeline:
/// Workspace Resolve → Package Resolve → Swift Build → Verify (VUACheck) →
/// Export Build → App Bundle → Artifact.
public enum BuildStage: String, CaseIterable, Sendable, Codable, Identifiable {
    case workspaceResolve
    case packageResolve
    case swiftBuild
    case verify
    case exportBuild
    case appBundle
    case artifact

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .workspaceResolve: return "Workspace Resolve"
        case .packageResolve: return "Package Resolve"
        case .swiftBuild: return "Swift Build"
        case .verify: return "Verify (VUACheck)"
        case .exportBuild: return "Export Build"
        case .appBundle: return "App Bundle"
        case .artifact: return "Artifact"
        }
    }

    /// Canonical pipeline order.
    public static var pipeline: [BuildStage] { allCases }
}

/// Status of a stage in a concrete pipeline run.
public enum BuildStageStatus: String, Sendable, Codable {
    case pending, running, succeeded, failed, skipped
}

/// A concrete pipeline run: ordered stages with statuses and optional notes.
public struct BuildPipeline: Sendable {
    public struct Entry: Sendable, Identifiable {
        public var id: BuildStage { stage }
        public var stage: BuildStage
        public var status: BuildStageStatus
        public var note: String?
        public init(stage: BuildStage, status: BuildStageStatus = .pending, note: String? = nil) {
            self.stage = stage
            self.status = status
            self.note = note
        }
    }
    public var entries: [Entry]

    public init(stages: [BuildStage] = BuildStage.pipeline) {
        entries = stages.map { Entry(stage: $0) }
    }

    public mutating func set(_ stage: BuildStage, _ status: BuildStageStatus, note: String? = nil) {
        guard let i = entries.firstIndex(where: { $0.stage == stage }) else { return }
        entries[i].status = status
        if let note { entries[i].note = note }
    }

    public var failed: Bool { entries.contains { $0.status == .failed } }
}

/// A diagnostic about build configuration, toolchain, or generated code.
public struct BuildDiagnostic: Hashable, Sendable, Identifiable {
    public enum Severity: Int, Comparable, Sendable {
        case info, warning, error
        public static func < (l: Severity, r: Severity) -> Bool { l.rawValue < r.rawValue }
        public var label: String { ["Info", "Warning", "Error"][rawValue] }
    }
    public enum Code: String, Sendable {
        case missingPackageManifest
        case packageResolvedMissing
        case packageResolvedStale
        case invalidGeneratedImport
        case missingVUAControls
        case previewMacroCLTIncompatible
        case commandLineToolsOnly
        case missingPlatformDeclaration
        case buildFailed
        case staleBuildCache
    }
    public let id = UUID()
    public var severity: Severity
    public var code: Code
    public var message: String
    /// A human suggestion for fixing the problem.
    public var suggestion: String?

    public init(severity: Severity, code: Code, message: String, suggestion: String? = nil) {
        self.severity = severity
        self.code = code
        self.message = message
        self.suggestion = suggestion
    }
}

/// What Swift toolchain this machine actually has — full Xcode vs Command
/// Line Tools only changes what builds (XCTest, #Preview, xcodebuild).
public struct ToolchainInfo: Sendable {
    public var swiftVersionLine: String?
    public var developerDir: String?
    public var hasFullXcode: Bool

    public var commandLineToolsOnly: Bool { !hasFullXcode }

    /// Short version like "6.0.3" pulled out of the version line, if present.
    public var swiftVersion: String? {
        guard let line = swiftVersionLine,
              let range = line.range(of: "Swift version ") else { return nil }
        return line[range.upperBound...].split(separator: " ").first.map(String.init)
    }

    public init(swiftVersionLine: String? = nil, developerDir: String? = nil, hasFullXcode: Bool = false) {
        self.swiftVersionLine = swiftVersionLine
        self.developerDir = developerDir
        self.hasFullXcode = hasFullXcode
    }
}

/// A resolved snapshot of "what would a build here look like?" — command,
/// directory, toolchain, manifest/lockfile state, and diagnostics. Computed
/// before builds so failures are explainable rather than mysterious.
public struct BuildContext: Sendable {
    public var kind: BuildKind
    public var workingDirectory: URL
    public var product: String?
    public var toolchain: ToolchainInfo
    public var packageManifest: URL?
    public var packageResolved: URL?
    public var hasBuildCache: Bool
    public var command: [String]
    public var diagnostics: [BuildDiagnostic]

    public var commandLine: String { command.joined(separator: " ") }
    public var hasBlockingIssue: Bool { diagnostics.contains { $0.severity == .error } }
}
