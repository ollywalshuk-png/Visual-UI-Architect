import Foundation
import VUACore
import ValidationEngine
import GitEngine

/// Outcome of the safe-apply pipeline. Mirrors the brief's required flow:
/// Visual Edit → Validate → Write → Swift Build → Git Diff → (Commit option).
public struct SafeApplyResult: Sendable {
    public enum Stage: String, Sendable { case validate, preflight, write, build, diff }
    /// The stage at which the pipeline stopped, or nil if it ran to completion.
    public var blockedAt: Stage?
    public var validation: ValidationReport
    public var filesWritten: [String]
    public var buildRan: Bool
    public var buildPassed: Bool
    public var buildOutput: String
    public var diff: String
    public var previewOnly: Bool
    public var plannedChanges: [String]
    public var unsupportedRegions: [String]

    public var succeeded: Bool { blockedAt == nil }
    public var canCommit: Bool { succeeded && !filesWritten.isEmpty }
}

public enum SafeApplyError: Error, CustomStringConvertible {
    case fileMissing(String)
    case readFailed(String)
    case writeFailed(String)

    public var description: String {
        switch self {
        case .fileMissing(let p): return "Source file not found: \(p)"
        case .readFailed(let p): return "Could not read: \(p)"
        case .writeFailed(let p): return "Could not write: \(p)"
        }
    }
}

/// Orchestrates writing visual edits back to source safely. Never commits
/// automatically — it surfaces a diff and leaves the commit to the user.
public struct SafeApplyPipeline {
    private let validator = ValidationService()
    private let writer = SourceFidelityWriter()

    public init() {}

    /// Applies the document's bound-layer frames back to their source files.
    /// - Parameters:
    ///   - repoRoot: repository root (for resolving relative paths, build, diff).
    ///   - runBuild: run `swift build` after writing when the repo is a package.
    public func apply(document: Document, repoRoot: URL, runBuild: Bool) throws -> SafeApplyResult {
        try run(document: document, repoRoot: repoRoot, runBuild: runBuild, previewOnly: false)
    }

    /// Computes the exact partial-file updates without writing them. The result
    /// carries the same validation/preflight diagnostics and a unified preview
    /// diff so users can review source changes before Apply.
    public func preview(document: Document, repoRoot: URL) throws -> SafeApplyResult {
        try run(document: document, repoRoot: repoRoot, runBuild: false, previewOnly: true)
    }

    private func run(document: Document, repoRoot: URL, runBuild: Bool, previewOnly: Bool) throws -> SafeApplyResult {
        // 1. Validate — block on errors before touching source.
        let report = validator.validate(document)
        if report.hasErrors {
            return SafeApplyResult(blockedAt: .validate, validation: report,
                                   filesWritten: [], buildRan: false, buildPassed: false,
                                   buildOutput: "", diff: "", previewOnly: previewOnly,
                                   plannedChanges: [], unsupportedRegions: [])
        }

        // 2. Group bound layers by source file: anchor → frame, and anchor →
        //    image asset name (for image/background layers with an asset).
        var framesByFile: [String: [String: VRect]] = [:]
        var imagesByFile: [String: [String: String]] = [:]
        for layer in document.allLayers {
            guard let binding = layer.binding else { continue }
            framesByFile[binding.filePath, default: [:]][binding.anchorID] = layer.frame
            if (layer.kind == .image || layer.kind == .background),
               let assetID = layer.assetID, let asset = document.asset(id: assetID) {
                imagesByFile[binding.filePath, default: [:]][binding.anchorID] = asset.name
            }
        }

        // 3. Preflight every target file (Phase 12): merge markers, read-only,
        //    ambiguous/missing anchors. Block before the first byte is written.
        let allFiles = Set(framesByFile.keys).union(imagesByFile.keys)
        let safety = SourceSafety()
        var preflightIssues: [ValidationIssue] = []
        var unsupportedRegions: [String] = []
        for relPath in allFiles {
            let url = relPath.hasPrefix("/")
                ? URL(fileURLWithPath: relPath)
                : repoRoot.appendingPathComponent(relPath)
            let anchors = Array(Set((framesByFile[relPath] ?? [:]).keys).union((imagesByFile[relPath] ?? [:]).keys))
            let result = safety.preflight(fileURL: url, expectedAnchors: anchors)
            unsupportedRegions.append(contentsOf: result.findings
                .filter { $0.code == .unsupportedRegion }
                .map(\.message))
            for finding in result.findings where finding.severity == .blocker {
                preflightIssues.append(ValidationIssue(
                    severity: .error, category: .structure,
                    message: finding.message,
                    recommendation: nil, layerIDs: []))
            }
        }
        if !preflightIssues.isEmpty {
            return SafeApplyResult(blockedAt: .preflight,
                                   validation: ValidationReport(issues: report.issues + preflightIssues),
                                   filesWritten: [], buildRan: false, buildPassed: false,
                                   buildOutput: "", diff: "", previewOnly: previewOnly,
                                   plannedChanges: [], unsupportedRegions: unsupportedRegions)
        }

        // 4. Write each file with source fidelity (positions then image names).
        var written: [String] = []
        var previewDiffs: [String] = []
        var plannedChanges: [String] = []
        for relPath in allFiles {
            let url = relPath.hasPrefix("/")
                ? URL(fileURLWithPath: relPath)
                : repoRoot.appendingPathComponent(relPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SafeApplyError.fileMissing(relPath)
            }
            guard let source = try? String(contentsOf: url, encoding: .utf8) else {
                throw SafeApplyError.readFailed(relPath)
            }
            var updated = source
            if let frames = framesByFile[relPath] {
                updated = try writer.updatePositions(in: updated, changes: frames)
            }
            if let images = imagesByFile[relPath] {
                updated = try writer.updateImageNames(in: updated, changes: images)
            }
            if updated != source {
                updated = Self.preserveLineEndings(from: source, in: updated)
                let changedAnchors = Array(Set((framesByFile[relPath] ?? [:]).keys)
                    .union((imagesByFile[relPath] ?? [:]).keys)).sorted()
                plannedChanges.append(contentsOf: changedAnchors.map { anchor in
                    if let line = SourceSafety.lineNumber(of: anchor, in: source) {
                        return "\(relPath):\(line) \(anchor)"
                    }
                    return "\(relPath) \(anchor)"
                })
                previewDiffs.append(Self.unifiedDiff(old: source, new: updated, filePath: relPath))
                if !previewOnly {
                    do { try updated.write(to: url, atomically: true, encoding: .utf8) }
                    catch { throw SafeApplyError.writeFailed(relPath) }
                    written.append(relPath)
                }
            }
        }

        if previewOnly {
            return SafeApplyResult(blockedAt: nil, validation: report,
                                   filesWritten: [], buildRan: false, buildPassed: true,
                                   buildOutput: "", diff: previewDiffs.joined(separator: "\n"),
                                   previewOnly: true, plannedChanges: plannedChanges,
                                   unsupportedRegions: unsupportedRegions)
        }

        // 4. Build (optional, only for SwiftPM packages).
        var buildRan = false, buildPassed = true, buildOutput = ""
        if runBuild, FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("Package.swift").path) {
            buildRan = true
            let result = runSwiftBuild(in: repoRoot)
            buildPassed = result.ok
            buildOutput = result.output
            if !buildPassed {
                return SafeApplyResult(blockedAt: .build, validation: report,
                                       filesWritten: written, buildRan: true, buildPassed: false,
                                       buildOutput: buildOutput, diff: "", previewOnly: false,
                                       plannedChanges: plannedChanges, unsupportedRegions: unsupportedRegions)
            }
        }

        // 5. Diff (best-effort; empty if not a git repo).
        var diff = ""
        let repo = GitRepository(repositoryURL: repoRoot)
        if repo.isGitRepository() { diff = (try? repo.diff()) ?? "" }

        return SafeApplyResult(blockedAt: nil, validation: report,
                               filesWritten: written, buildRan: buildRan, buildPassed: buildPassed,
                               buildOutput: buildOutput, diff: diff.isEmpty ? previewDiffs.joined(separator: "\n") : diff,
                               previewOnly: false, plannedChanges: plannedChanges,
                               unsupportedRegions: unsupportedRegions)
    }

    private static func preserveLineEndings(from original: String, in updated: String) -> String {
        original.contains("\r\n") ? updated.replacingOccurrences(of: "\n", with: "\r\n") : updated
    }

    private static func unifiedDiff(old: String, new: String, filePath: String) -> String {
        let oldLines = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out = ["--- a/\(filePath)", "+++ b/\(filePath)"]
        let maxCount = max(oldLines.count, newLines.count)
        for i in 0..<maxCount {
            let lhs = i < oldLines.count ? oldLines[i] : nil
            let rhs = i < newLines.count ? newLines[i] : nil
            guard lhs != rhs else { continue }
            out.append("@@ line \(i + 1) @@")
            if let lhs { out.append("-\(lhs)") }
            if let rhs { out.append("+\(rhs)") }
        }
        return out.count > 2 ? out.joined(separator: "\n") : ""
    }

    private func runSwiftBuild(in root: URL) -> (ok: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "build"]
        process.currentDirectoryURL = root
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (false, "Failed to launch swift build: \(error)") }
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus == 0, output)
    }
}
