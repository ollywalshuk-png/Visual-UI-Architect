import Foundation
import GitEngine
import VUACore

public enum TargetAppInjection {
    public struct Request: Sendable {
        public var repoRoot: URL
        public var targetFile: String
        public var generatedSource: String
        public var expectedHash: String?
        public var allowDirtyRepo: Bool
        public var runBuild: Bool

        public init(repoRoot: URL, targetFile: String, generatedSource: String,
                    expectedHash: String? = nil, allowDirtyRepo: Bool = false, runBuild: Bool = false) {
            self.repoRoot = repoRoot
            self.targetFile = targetFile
            self.generatedSource = generatedSource
            self.expectedHash = expectedHash
            self.allowDirtyRepo = allowDirtyRepo
            self.runBuild = runBuild
        }
    }

    public struct Result: Sendable {
        public var targetURL: URL
        public var previewDiff: String
        public var gitDiff: String
        public var assetDependencies: [String]
        public var diagnostics: [Diagnostic]
        public var buildRan: Bool
        public var buildPassed: Bool
        public var buildOutput: String
        public var rollbackPlan: [String]
        public var wroteFile: Bool

        public var hasBlocker: Bool { diagnostics.contains { $0.severity == .blocker } }
    }

    public struct Diagnostic: Hashable, Sendable, Identifiable {
        public enum Severity: String, Sendable { case info, warning, blocker }
        public enum Code: String, Sendable {
            case targetMissing, dirtyRepository, hashMismatch, sourcePreflight, buildFailed, noInjectionMarker
        }
        public let id = UUID()
        public var severity: Severity
        public var code: Code
        public var message: String
    }

    public static func preview(_ request: Request) -> Result {
        run(request, write: false)
    }

    public static func apply(_ request: Request) -> Result {
        run(request, write: true)
    }

    private static func run(_ request: Request, write: Bool) -> Result {
        let targetURL = request.targetFile.hasPrefix("/")
            ? URL(fileURLWithPath: request.targetFile)
            : request.repoRoot.appendingPathComponent(request.targetFile)
        var diagnostics: [Diagnostic] = []
        var original = ""
        if let text = try? String(contentsOf: targetURL, encoding: .utf8) {
            original = text
        } else {
            diagnostics.append(.init(severity: .blocker, code: .targetMissing,
                                     message: "Target file is missing or unreadable: \(targetURL.path)"))
        }

        let repo = GitRepository(repositoryURL: request.repoRoot)
        if repo.isGitRepository(),
           let status = try? repo.status(), !status.isEmpty, !request.allowDirtyRepo {
            diagnostics.append(.init(severity: .blocker, code: .dirtyRepository,
                                     message: "Target repository has uncommitted changes; confirm dirty-repo injection before writing."))
        }

        if !original.isEmpty, let expected = request.expectedHash,
           SourceSafety.hash(of: original) != expected {
            diagnostics.append(.init(severity: .blocker, code: .hashMismatch,
                                     message: "Target file hash changed since preview; refresh before injection."))
        }

        if !original.isEmpty {
            for finding in SourceSafety.inspect(source: original, fileName: targetURL.lastPathComponent) {
                if finding.severity == .blocker {
                    diagnostics.append(.init(severity: .blocker, code: .sourcePreflight, message: finding.message))
                }
            }
        }

        let injected = replaceInjectionRegion(in: original, with: request.generatedSource)
        if !original.isEmpty, injected == original, !original.contains("// VUA:BEGIN-INJECTION") {
            diagnostics.append(.init(severity: .warning, code: .noInjectionMarker,
                                     message: "No VUA injection markers found; generated source will replace the full target file."))
        }
        let finalSource = original.contains("// VUA:BEGIN-INJECTION") ? injected : request.generatedSource
        let previewDiff = unifiedDiff(old: original, new: finalSource, filePath: request.targetFile)
        let assets = assetDependencies(in: request.generatedSource)
        var buildRan = false
        var buildPassed = true
        var buildOutput = ""

        if write && diagnostics.allSatisfy({ $0.severity != .blocker }) {
            do { try preserveLineEndings(from: original, in: finalSource).write(to: targetURL, atomically: true, encoding: .utf8) }
            catch {
                diagnostics.append(.init(severity: .blocker, code: .targetMissing,
                                         message: "Could not write target file: \(error)"))
            }
            if request.runBuild {
                buildRan = true
                let result = swiftBuild(in: request.repoRoot)
                buildPassed = result.ok
                buildOutput = result.output
                if !buildPassed {
                    diagnostics.append(.init(severity: .blocker, code: .buildFailed,
                                             message: "swift build failed after injection."))
                }
            }
        }

        let gitDiff = repo.isGitRepository() ? ((try? repo.diff(path: request.targetFile)) ?? "") : ""
        return Result(targetURL: targetURL, previewDiff: previewDiff, gitDiff: gitDiff,
                      assetDependencies: assets, diagnostics: diagnostics,
                      buildRan: buildRan, buildPassed: buildPassed, buildOutput: buildOutput,
                      rollbackPlan: rollbackPlan(for: request.targetFile, repoRoot: request.repoRoot),
                      wroteFile: write && diagnostics.allSatisfy { $0.severity != .blocker })
    }

    private static func replaceInjectionRegion(in source: String, with generated: String) -> String {
        guard let start = source.range(of: "// VUA:BEGIN-INJECTION"),
              let end = source.range(of: "// VUA:END-INJECTION"),
              start.lowerBound < end.upperBound else { return source }
        return String(source[..<start.upperBound]) + "\n" + generated + "\n" + String(source[end.lowerBound...])
    }

    private static func assetDependencies(in source: String) -> [String] {
        var out: [String] = []
        let marker = "Image(\""
        var index = source.startIndex
        while let range = source.range(of: marker, range: index..<source.endIndex) {
            let rest = source[range.upperBound...]
            guard let close = rest.firstIndex(of: "\"") else { break }
            let name = String(rest[..<close])
            if !out.contains(name) { out.append(name) }
            index = close
        }
        return out
    }

    private static func unifiedDiff(old: String, new: String, filePath: String) -> String {
        let oldLines = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out = ["--- a/\(filePath)", "+++ b/\(filePath)"]
        for i in 0..<max(oldLines.count, newLines.count) where (i < oldLines.count ? oldLines[i] : nil) != (i < newLines.count ? newLines[i] : nil) {
            out.append("@@ line \(i + 1) @@")
            if i < oldLines.count { out.append("-\(oldLines[i])") }
            if i < newLines.count { out.append("+\(newLines[i])") }
        }
        return out.count > 2 ? out.joined(separator: "\n") : ""
    }

    private static func preserveLineEndings(from original: String, in updated: String) -> String {
        original.contains("\r\n") ? updated.replacingOccurrences(of: "\n", with: "\r\n") : updated
    }

    private static func rollbackPlan(for targetFile: String, repoRoot: URL) -> [String] {
        let repo = GitRepository(repositoryURL: repoRoot)
        if repo.isGitRepository() { return ["git restore \(targetFile)", "git diff -- \(targetFile)"] }
        return ["Restore \(targetFile) from your last backup or source-control checkpoint."]
    }

    private static func swiftBuild(in root: URL) -> (ok: Bool, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["swift", "build"]
        p.currentDirectoryURL = root
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (false, "Failed to launch swift build: \(error)") }
        p.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (p.terminationStatus == 0, output)
    }
}
