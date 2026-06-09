import Foundation

/// A diagnostic about the selected workspace/repo.
public struct WorkspaceWarning: Hashable, Sendable, Identifiable {
    public enum Severity: Int, Comparable, Sendable {
        case info, warning, error
        public static func < (l: Severity, r: Severity) -> Bool { l.rawValue < r.rawValue }
        public var label: String { ["Info", "Warning", "Error"][rawValue] }
    }
    public enum Code: String, Sendable {
        case notAGitRepo
        case nestedRepos
        case multipleRepos
        case multiplePackages
        case multipleXcodeProjects
        case multipleWorkspaces
        case generatedExportFolder
        case buildFolderSelected
        case dependencyFolderSelected
        case dirtyTree
        case detachedHEAD
        case operationInProgress     // merge / rebase
        case indexLock
        case noUISources
        case staleScan
    }
    public let id = UUID()
    public var severity: Severity
    public var code: Code
    public var message: String
}

/// A resolved snapshot of "what am I about to write to?" — computed before any
/// Apply / Export / Commit so the app never edits the wrong repo or a stale,
/// generated, or build directory.
public struct WorkspaceContext: Sendable {
    public var rootURL: URL
    public var isGitRepo: Bool
    public var repoRoot: URL?
    public var branch: String?
    public var latestCommit: String?
    public var isDirty: Bool
    public var detachedHEAD: Bool
    public var operationInProgress: String?   // "merge" / "rebase" / nil
    public var hasIndexLock: Bool
    public var packageManifests: [URL]
    public var xcodeProjects: [URL]
    public var xcodeWorkspaces: [URL]
    public var nestedGitRepos: [URL]
    public var looksLikeGeneratedExport: Bool
    public var looksLikeBuildFolder: Bool
    public var looksLikeDependencyFolder: Bool
    public var swiftFileCount: Int
    public var uiSourceCount: Int
    public var lastScan: Date
    public var warnings: [WorkspaceWarning]

    /// 0…1 confidence that this is a safe, intended source repository.
    public var confidence: Double {
        var score = 1.0
        if !isGitRepo { score -= 0.25 }
        if looksLikeGeneratedExport { score -= 0.5 }
        if looksLikeBuildFolder || looksLikeDependencyFolder { score -= 0.6 }
        if packageManifests.count > 1 { score -= 0.15 }
        if !nestedGitRepos.isEmpty { score -= 0.1 }
        if detachedHEAD { score -= 0.1 }
        if operationInProgress != nil { score -= 0.15 }
        if hasIndexLock { score -= 0.1 }
        if uiSourceCount == 0 { score -= 0.1 }
        return Swift.min(1, Swift.max(0, score))
    }

    public var isSafeToWrite: Bool {
        !looksLikeGeneratedExport && !looksLikeBuildFolder && !looksLikeDependencyFolder
            && operationInProgress == nil && !hasIndexLock
    }

    public var hasBlockingIssue: Bool { warnings.contains { $0.severity == .error } }
}
