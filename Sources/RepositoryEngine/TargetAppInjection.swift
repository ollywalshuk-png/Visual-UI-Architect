import Foundation
import GitEngine
import VUACore

public enum TargetAppInjection {
    public struct AssetCopy: Hashable, Sendable {
        public var name: String
        public var sourceURL: URL
        public var destinationFileName: String

        public init(name: String, sourceURL: URL, destinationFileName: String? = nil) {
            self.name = name
            self.sourceURL = sourceURL
            self.destinationFileName = destinationFileName ?? sourceURL.lastPathComponent
        }
    }

    public struct AssetCopyResult: Hashable, Sendable {
        public var name: String
        public var sourceURL: URL
        public var destinationURL: URL
        public var destinationRelativePath: String
        public var byteCount: Int64
        public var alreadyExists: Bool
        public var didCopy: Bool
    }

    public struct Request: Sendable {
        public var repoRoot: URL
        public var targetFile: String
        public var generatedSource: String
        public var expectedHash: String?
        public var allowDirtyRepo: Bool
        public var runBuild: Bool
        public var allowFullFileReplacement: Bool
        public var allowCreateFile: Bool
        public var assetCopies: [AssetCopy]
        public var assetDestinationDirectory: String?
        public var allowAssetCopy: Bool

        public init(repoRoot: URL, targetFile: String, generatedSource: String,
                    expectedHash: String? = nil, allowDirtyRepo: Bool = false, runBuild: Bool = false,
                    allowFullFileReplacement: Bool = false, allowCreateFile: Bool = false,
                    assetCopies: [AssetCopy] = [], assetDestinationDirectory: String? = nil,
                    allowAssetCopy: Bool = false) {
            self.repoRoot = repoRoot
            self.targetFile = targetFile
            self.generatedSource = generatedSource
            self.expectedHash = expectedHash
            self.allowDirtyRepo = allowDirtyRepo
            self.runBuild = runBuild
            self.allowFullFileReplacement = allowFullFileReplacement
            self.allowCreateFile = allowCreateFile
            self.assetCopies = assetCopies
            self.assetDestinationDirectory = assetDestinationDirectory
            self.allowAssetCopy = allowAssetCopy
        }
    }

    public struct Result: Sendable {
        public enum ReplacementMode: String, Sendable { case markerRegion, fullFile, newFile }
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
        public var assetCopyResults: [AssetCopyResult]
        public var replacementMode: ReplacementMode
        public var changedLineCount: Int

        public var hasBlocker: Bool { diagnostics.contains { $0.severity == .blocker } }
        public var summary: String {
            let mode = switch replacementMode {
            case .markerRegion: "Marker-region"
            case .fullFile: "Full-file"
            case .newFile: "New-file"
            }
            let assetCopySummary = assetCopyResults.isEmpty ? "" : ", \(assetCopyResults.count) asset copy target(s)"
            return "\(mode) injection, \(changedLineCount) changed line(s), \(assetDependencies.count) asset dependency(ies)\(assetCopySummary)."
        }
    }

    public struct Diagnostic: Hashable, Sendable, Identifiable {
        public enum Severity: String, Sendable { case info, warning, blocker }
        public enum Code: String, Sendable {
            case targetMissing, targetOutsideRepository, unsupportedTarget, dirtyRepository, hashMismatch
            case sourcePreflight, buildFailed, noInjectionMarker, fullFileReplacementBlocked, createFileBlocked
            case assetCopyBlocked, assetSourceMissing, assetDestinationConflict
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
        let resolvedTarget = resolveTarget(repoRoot: request.repoRoot, targetFile: request.targetFile)
        let targetURL = resolvedTarget.url
        let diffPath = resolvedTarget.relativePath
        var diagnostics: [Diagnostic] = []
        var original = ""

        let targetExists = FileManager.default.fileExists(atPath: targetURL.path)
        if !resolvedTarget.isInsideRepository {
            diagnostics.append(.init(
                severity: .blocker, code: .targetOutsideRepository,
                message: "Target file must stay inside the selected repository: \(request.targetFile)"))
        }
        if !request.targetFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           targetURL.pathExtension.lowercased() != "swift" {
            diagnostics.append(.init(
                severity: .blocker, code: .unsupportedTarget,
                message: "Target injection only supports Swift source files."))
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            diagnostics.append(.init(
                severity: .blocker, code: .unsupportedTarget,
                message: "Target injection cannot write into a directory."))
        }

        if diagnostics.allSatisfy({ $0.code != .targetOutsideRepository && $0.code != .unsupportedTarget }) {
            if let text = try? String(contentsOf: targetURL, encoding: .utf8) {
                original = text
            } else if !targetExists, request.allowCreateFile {
                // Missing target is handled below as an explicit new-file write.
            } else {
                diagnostics.append(.init(
                    severity: .blocker,
                    code: targetExists ? .targetMissing : .createFileBlocked,
                    message: targetExists
                        ? "Target file is missing or unreadable: \(targetURL.path)"
                        : "Target file is missing; enable new-file creation before writing \(targetURL.path)."))
            }
        }
        let existingFileReadable = targetExists && diagnostics.allSatisfy { $0.code != .targetMissing }
        let isNewFile = !targetExists && request.allowCreateFile &&
            diagnostics.allSatisfy { ![.targetOutsideRepository, .unsupportedTarget, .targetMissing].contains($0.code) }
        if isNewFile {
            diagnostics.removeAll { $0.code == .targetMissing || $0.code == .createFileBlocked }
            diagnostics.append(.init(severity: .info, code: .noInjectionMarker,
                                     message: "Target file will be created with VUA generated-file ownership markers."))
        }

        let repo = GitRepository(repositoryURL: request.repoRoot)
        if repo.isGitRepository(),
           let status = try? repo.status(), !status.isEmpty, !request.allowDirtyRepo {
            diagnostics.append(.init(severity: .blocker, code: .dirtyRepository,
                                     message: "Target repository has uncommitted changes; confirm dirty-repo injection before writing."))
        }

        if existingFileReadable, let expected = request.expectedHash,
           SourceSafety.hash(of: original) != expected {
            diagnostics.append(.init(severity: .blocker, code: .hashMismatch,
                                     message: "Target file hash changed since preview; refresh before injection."))
        }

        if existingFileReadable {
            for finding in SourceSafety.inspect(source: original, fileName: targetURL.lastPathComponent) {
                if finding.severity == .blocker {
                    diagnostics.append(.init(severity: .blocker, code: .sourcePreflight, message: finding.message))
                }
            }
        }

        let hasMarkers = original.contains("// VUA:BEGIN-INJECTION") && original.contains("// VUA:END-INJECTION")
        let injected = replaceInjectionRegion(in: original, with: request.generatedSource)
        if existingFileReadable, injected == original, !hasMarkers {
            if request.allowFullFileReplacement {
                diagnostics.append(.init(severity: .warning, code: .noInjectionMarker,
                                         message: "No VUA injection markers found; generated source will replace the full target file."))
            } else {
                diagnostics.append(.init(severity: .blocker, code: .fullFileReplacementBlocked,
                                         message: "No VUA injection markers found; enable full-file replacement before writing."))
            }
        }
        let finalSource = isNewFile ? wrapGeneratedFile(request.generatedSource) : (hasMarkers ? injected : request.generatedSource)
        let replacementMode: Result.ReplacementMode = isNewFile ? .newFile : (hasMarkers ? .markerRegion : .fullFile)
        let previewDiff = unifiedDiff(old: original, new: finalSource, filePath: diffPath)
        let changedLineCount = previewDiff.split(separator: "\n").filter {
            ($0.hasPrefix("+") && !$0.hasPrefix("+++")) || ($0.hasPrefix("-") && !$0.hasPrefix("---"))
        }.count
        let assets = assetDependencies(in: request.generatedSource)
        let assetCopyPlan = prepareAssetCopies(request: request, diagnostics: &diagnostics)
        var assetCopyResults = assetCopyPlan.map { $0.result(didCopy: false) }
        var buildRan = false
        var buildPassed = true
        var buildOutput = ""
        var didWriteFile = false

        if write && diagnostics.allSatisfy({ $0.severity != .blocker }) {
            var targetWriteSucceeded = false
            do {
                if isNewFile {
                    try FileManager.default.createDirectory(
                        at: targetURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true)
                }
                try preserveLineEndings(from: original, in: finalSource).write(to: targetURL, atomically: true, encoding: .utf8)
                targetWriteSucceeded = true
            }
            catch {
                diagnostics.append(.init(severity: .blocker, code: .targetMissing,
                                         message: "Could not write target file: \(error)"))
            }
            didWriteFile = targetWriteSucceeded
            if targetWriteSucceeded && diagnostics.allSatisfy({ $0.severity != .blocker }) {
                do {
                    assetCopyResults = try copyAssets(assetCopyPlan)
                } catch let error as AssetCopyWriteError {
                    diagnostics.append(.init(severity: .blocker, code: .assetCopyBlocked, message: error.message))
                } catch {
                    diagnostics.append(.init(severity: .blocker, code: .assetCopyBlocked,
                                             message: "Could not copy target app asset: \(error)"))
                }
            }
            if request.runBuild && diagnostics.allSatisfy({ $0.severity != .blocker }) {
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

        let gitDiff = repo.isGitRepository() && resolvedTarget.isInsideRepository
            ? combined([try? repo.diff(path: diffPath)] + assetCopyPlan.map { try? repo.diff(path: $0.destinationRelativePath) })
            : ""
        let rollback = rollbackPlan(for: diffPath, repoRoot: request.repoRoot, isNewFile: isNewFile) +
            assetCopyPlan.flatMap { assetRollbackPlan(for: $0, repoRoot: request.repoRoot) }
        return Result(targetURL: targetURL, previewDiff: previewDiff, gitDiff: gitDiff,
                      assetDependencies: assets, diagnostics: diagnostics,
                      buildRan: buildRan, buildPassed: buildPassed, buildOutput: buildOutput,
                      rollbackPlan: rollback,
                      wroteFile: didWriteFile,
                      assetCopyResults: assetCopyResults,
                      replacementMode: replacementMode,
                      changedLineCount: changedLineCount)
    }

    private struct ResolvedTarget {
        var url: URL
        var relativePath: String
        var isInsideRepository: Bool
    }

    private struct AssetCopyPlan {
        var name: String
        var sourceURL: URL
        var destinationURL: URL
        var destinationRelativePath: String
        var byteCount: Int64
        var alreadyExists: Bool

        func result(didCopy: Bool) -> AssetCopyResult {
            AssetCopyResult(
                name: name,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                destinationRelativePath: destinationRelativePath,
                byteCount: byteCount,
                alreadyExists: alreadyExists,
                didCopy: didCopy)
        }
    }

    private struct AssetCopyWriteError: Error {
        var message: String
    }

    private static func resolveTarget(repoRoot: URL, targetFile: String) -> ResolvedTarget {
        let root = repoRoot.standardizedFileURL.resolvingSymlinksInPath()
        let trimmed = targetFile.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.hasPrefix("/")
            ? URL(fileURLWithPath: trimmed)
            : root.appendingPathComponent(trimmed)
        let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path
        let targetPath = resolved.path
        let inside = targetPath == rootPath || targetPath.hasPrefix(rootPath + "/")
        let relative = inside ? relativePath(from: root, to: resolved) : targetFile
        return ResolvedTarget(url: resolved, relativePath: relative.isEmpty ? "." : relative, isInsideRepository: inside)
    }

    private static func prepareAssetCopies(request: Request, diagnostics: inout [Diagnostic]) -> [AssetCopyPlan] {
        guard !request.assetCopies.isEmpty else { return [] }
        guard request.allowAssetCopy else {
            diagnostics.append(.init(severity: .blocker, code: .assetCopyBlocked,
                                     message: "Asset copying requires explicit opt-in before writing target app resources."))
            return []
        }
        guard let rawDestination = request.assetDestinationDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawDestination.isEmpty else {
            diagnostics.append(.init(severity: .blocker, code: .assetCopyBlocked,
                                     message: "Asset copying requires a target app asset destination directory."))
            return []
        }

        let resolvedDirectory = resolveTarget(repoRoot: request.repoRoot, targetFile: rawDestination)
        guard resolvedDirectory.isInsideRepository else {
            diagnostics.append(.init(severity: .blocker, code: .assetCopyBlocked,
                                     message: "Asset destination must stay inside the selected repository: \(rawDestination)"))
            return []
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: resolvedDirectory.url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            diagnostics.append(.init(severity: .blocker, code: .assetDestinationConflict,
                                     message: "Asset destination is an existing file, not a directory: \(resolvedDirectory.url.path)"))
            return []
        }

        var plans: [AssetCopyPlan] = []
        var seenDestinations = Set<String>()
        for copy in request.assetCopies {
            let sourceURL = copy.sourceURL.standardizedFileURL.resolvingSymlinksInPath()
            var sourceIsDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &sourceIsDirectory),
                  !sourceIsDirectory.boolValue else {
                diagnostics.append(.init(severity: .blocker, code: .assetSourceMissing,
                                         message: "Asset source is missing or is a directory: \(copy.sourceURL.path)"))
                continue
            }

            let destinationName = copy.destinationFileName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !destinationName.isEmpty, !destinationName.hasPrefix("/") else {
                diagnostics.append(.init(severity: .blocker, code: .assetDestinationConflict,
                                         message: "Asset destination filename must be relative: \(copy.destinationFileName)"))
                continue
            }

            let destinationURL = resolvedDirectory.url
                .appendingPathComponent(destinationName)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard isInside(destinationURL, root: resolvedDirectory.url) else {
                diagnostics.append(.init(severity: .blocker, code: .assetDestinationConflict,
                                         message: "Asset destination escapes the selected asset directory: \(destinationName)"))
                continue
            }
            let destinationRelativePath = relativePath(from: request.repoRoot, to: destinationURL)
            guard seenDestinations.insert(destinationRelativePath).inserted else {
                diagnostics.append(.init(severity: .blocker, code: .assetDestinationConflict,
                                         message: "Multiple assets target the same destination: \(destinationRelativePath)"))
                continue
            }

            var destinationIsDirectory: ObjCBool = false
            let destinationExists = FileManager.default.fileExists(atPath: destinationURL.path, isDirectory: &destinationIsDirectory)
            if destinationExists && destinationIsDirectory.boolValue {
                diagnostics.append(.init(severity: .blocker, code: .assetDestinationConflict,
                                         message: "Asset destination is an existing directory: \(destinationRelativePath)"))
                continue
            }
            if destinationExists && !filesMatch(sourceURL, destinationURL) {
                diagnostics.append(.init(severity: .blocker, code: .assetDestinationConflict,
                                         message: "Asset destination already exists with different contents: \(destinationRelativePath)"))
                continue
            }

            plans.append(AssetCopyPlan(
                name: copy.name,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                destinationRelativePath: destinationRelativePath,
                byteCount: byteCount(of: sourceURL),
                alreadyExists: destinationExists))
        }
        return plans
    }

    private static func relativePath(from root: URL, to target: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let targetComponents = target.standardizedFileURL.pathComponents
        guard targetComponents.count >= rootComponents.count,
              Array(targetComponents.prefix(rootComponents.count)) == rootComponents else {
            return target.path
        }
        return targetComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private static func isInside(_ url: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private static func replaceInjectionRegion(in source: String, with generated: String) -> String {
        guard let start = source.range(of: "// VUA:BEGIN-INJECTION"),
              let end = source.range(of: "// VUA:END-INJECTION"),
              start.lowerBound < end.upperBound else { return source }
        return String(source[..<start.upperBound]) + "\n" + generated + "\n" + String(source[end.lowerBound...])
    }

    private static func wrapGeneratedFile(_ generated: String) -> String {
        let trimmed = generated.trimmingCharacters(in: .newlines)
        return """
        // VUA:BEGIN-GENERATED-FILE
        // VUA:Owner=Visual UI Architect
        // VUA:EditPolicy=Regenerate from VUA or replace intentionally.
        \(trimmed)
        // VUA:END-GENERATED-FILE
        """
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

    private static func combined(_ diffs: [String?]) -> String {
        diffs.compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: "\n\n")
    }

    private static func preserveLineEndings(from original: String, in updated: String) -> String {
        original.contains("\r\n") ? updated.replacingOccurrences(of: "\n", with: "\r\n") : updated
    }

    private static func copyAssets(_ plans: [AssetCopyPlan]) throws -> [AssetCopyResult] {
        var results: [AssetCopyResult] = []
        for plan in plans {
            if plan.alreadyExists {
                results.append(plan.result(didCopy: false))
                continue
            }
            do {
                try FileManager.default.createDirectory(
                    at: plan.destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: plan.sourceURL, to: plan.destinationURL)
                results.append(plan.result(didCopy: true))
            } catch {
                throw AssetCopyWriteError(
                    message: "Could not copy asset '\(plan.name)' to \(plan.destinationRelativePath): \(error)")
            }
        }
        return results
    }

    private static func filesMatch(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let lhsData = try? Data(contentsOf: lhs),
              let rhsData = try? Data(contentsOf: rhs) else { return false }
        return lhsData == rhsData
    }

    private static func byteCount(of url: URL) -> Int64 {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        return size ?? 0
    }

    private static func rollbackPlan(for targetFile: String, repoRoot: URL, isNewFile: Bool) -> [String] {
        let repo = GitRepository(repositoryURL: repoRoot)
        let quoted = shellQuoted(targetFile)
        if isNewFile {
            if repo.isGitRepository() {
                return ["rm -f -- \(quoted)", "git status -- \(quoted)"]
            }
            return ["Delete \(targetFile) from the target app."]
        }
        if repo.isGitRepository() { return ["git restore -- \(quoted)", "git diff -- \(quoted)"] }
        return ["Restore \(targetFile) from your last backup or source-control checkpoint."]
    }

    private static func assetRollbackPlan(for plan: AssetCopyPlan, repoRoot: URL) -> [String] {
        let repo = GitRepository(repositoryURL: repoRoot)
        let quoted = shellQuoted(plan.destinationRelativePath)
        if plan.alreadyExists {
            if repo.isGitRepository() { return ["git restore -- \(quoted)", "git diff -- \(quoted)"] }
            return ["Restore \(plan.destinationRelativePath) from your last backup or source-control checkpoint."]
        }
        if repo.isGitRepository() { return ["rm -f -- \(quoted)", "git status -- \(quoted)"] }
        return ["Delete copied asset \(plan.destinationRelativePath) from the target app."]
    }

    private static func shellQuoted(_ value: String) -> String {
        if value.range(of: #"^[A-Za-z0-9_./-]+$"#, options: .regularExpression) != nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
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
