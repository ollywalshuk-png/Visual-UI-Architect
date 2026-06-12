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
        public var allowFullFileReplacement: Bool
        public var allowCreateFile: Bool
        public var routeFile: String?
        public var routeRegistration: String?
        public var allowRouteInsertion: Bool

        public init(repoRoot: URL, targetFile: String, generatedSource: String,
                    expectedHash: String? = nil, allowDirtyRepo: Bool = false, runBuild: Bool = false,
                    allowFullFileReplacement: Bool = false, allowCreateFile: Bool = false,
                    routeFile: String? = nil, routeRegistration: String? = nil,
                    allowRouteInsertion: Bool = false) {
            self.repoRoot = repoRoot
            self.targetFile = targetFile
            self.generatedSource = generatedSource
            self.expectedHash = expectedHash
            self.allowDirtyRepo = allowDirtyRepo
            self.runBuild = runBuild
            self.allowFullFileReplacement = allowFullFileReplacement
            self.allowCreateFile = allowCreateFile
            self.routeFile = routeFile
            self.routeRegistration = routeRegistration
            self.allowRouteInsertion = allowRouteInsertion
        }
    }

    public struct Result: Sendable {
        public enum ReplacementMode: String, Sendable { case markerRegion, fullFile, newFile }
        public var targetURL: URL
        public var routeURL: URL?
        public var previewDiff: String
        public var routePreviewDiff: String
        public var gitDiff: String
        public var assetDependencies: [String]
        public var diagnostics: [Diagnostic]
        public var buildRan: Bool
        public var buildPassed: Bool
        public var buildOutput: String
        public var rollbackPlan: [String]
        public var wroteFile: Bool
        public var routeInserted: Bool
        public var replacementMode: ReplacementMode
        public var changedLineCount: Int

        public var hasBlocker: Bool { diagnostics.contains { $0.severity == .blocker } }
        public var summary: String {
            let mode = switch replacementMode {
            case .markerRegion: "Marker-region"
            case .fullFile: "Full-file"
            case .newFile: "New-file"
            }
            let route = routeInserted ? ", route registration inserted" : ""
            return "\(mode) injection, \(changedLineCount) changed line(s), \(assetDependencies.count) asset dependency(ies)\(route)."
        }
    }

    public struct Diagnostic: Hashable, Sendable, Identifiable {
        public enum Severity: String, Sendable { case info, warning, blocker }
        public enum Code: String, Sendable {
            case targetMissing, targetOutsideRepository, unsupportedTarget, dirtyRepository, hashMismatch
            case sourcePreflight, buildFailed, noInjectionMarker, fullFileReplacementBlocked, createFileBlocked
            case routeFileMissing, routeInsertionBlocked, routeAlreadyRegistered
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
        var finalSource = isNewFile ? wrapGeneratedFile(request.generatedSource) : (hasMarkers ? injected : request.generatedSource)
        let replacementMode: Result.ReplacementMode = isNewFile ? .newFile : (hasMarkers ? .markerRegion : .fullFile)

        let routePlan = prepareRouteInsertion(
            request: request,
            targetURL: targetURL,
            targetSourceAfterInjection: finalSource,
            diagnostics: &diagnostics)
        if let routePlan, routePlan.isTargetFile {
            finalSource = routePlan.finalSource
        }

        let targetPreviewDiff = unifiedDiff(old: original, new: finalSource, filePath: diffPath)
        let routePreviewDiff = routePlan.map { plan in
            plan.isTargetFile ? plan.routePreviewDiff : unifiedDiff(
                old: plan.originalSource,
                new: plan.finalSource,
                filePath: plan.relativePath)
        } ?? ""
        let previewDiff = combined([targetPreviewDiff, routePlan?.isTargetFile == true ? "" : routePreviewDiff])
        let changedLineCount = previewDiff.split(separator: "\n").filter {
            ($0.hasPrefix("+") && !$0.hasPrefix("+++")) || ($0.hasPrefix("-") && !$0.hasPrefix("---"))
        }.count
        let assets = assetDependencies(in: request.generatedSource)
        var buildRan = false
        var buildPassed = true
        var buildOutput = ""
        var didWriteFile = false
        var didInsertRoute = false

        if write && diagnostics.allSatisfy({ $0.severity != .blocker }) {
            do {
                if isNewFile {
                    try FileManager.default.createDirectory(
                        at: targetURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true)
                }
                try preserveLineEndings(from: original, in: finalSource).write(to: targetURL, atomically: true, encoding: .utf8)
            }
            catch {
                diagnostics.append(.init(severity: .blocker, code: .targetMissing,
                                         message: "Could not write target file: \(error)"))
            }
            if diagnostics.allSatisfy({ $0.severity != .blocker }), let routePlan, routePlan.inserted {
                if routePlan.isTargetFile {
                    didInsertRoute = true
                } else {
                    do {
                    try preserveLineEndings(from: routePlan.originalSource, in: routePlan.finalSource)
                        .write(to: routePlan.url, atomically: true, encoding: .utf8)
                    didInsertRoute = true
                    } catch {
                        diagnostics.append(.init(severity: .blocker, code: .routeInsertionBlocked,
                                                 message: "Could not write route file: \(error)"))
                    }
                }
            }
            didWriteFile = diagnostics.allSatisfy { $0.severity != .blocker }
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

        let gitDiff = repo.isGitRepository() && resolvedTarget.isInsideRepository
            ? combined([try? repo.diff(path: diffPath), routePlan.flatMap { $0.isTargetFile ? nil : try? repo.diff(path: $0.relativePath) }])
            : ""
        let rollback = rollbackPlan(for: diffPath, repoRoot: request.repoRoot, isNewFile: isNewFile) +
            (routePlan.map { $0.isTargetFile ? [] : rollbackPlan(for: $0.relativePath, repoRoot: request.repoRoot, isNewFile: false) } ?? [])
        return Result(targetURL: targetURL, routeURL: routePlan?.url,
                      previewDiff: previewDiff, routePreviewDiff: routePreviewDiff, gitDiff: gitDiff,
                      assetDependencies: assets, diagnostics: diagnostics,
                      buildRan: buildRan, buildPassed: buildPassed, buildOutput: buildOutput,
                      rollbackPlan: rollback,
                      wroteFile: didWriteFile,
                      routeInserted: write ? didInsertRoute : (routePlan?.inserted ?? false),
                      replacementMode: replacementMode,
                      changedLineCount: changedLineCount)
    }

    private struct ResolvedTarget {
        var url: URL
        var relativePath: String
        var isInsideRepository: Bool
    }

    private struct RoutePlan {
        var url: URL
        var relativePath: String
        var originalSource: String
        var finalSource: String
        var routePreviewDiff: String
        var inserted: Bool
        var isTargetFile: Bool
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

    private static func prepareRouteInsertion(
        request: Request,
        targetURL: URL,
        targetSourceAfterInjection: String,
        diagnostics: inout [Diagnostic]
    ) -> RoutePlan? {
        guard let routeFile = request.routeFile?.trimmingCharacters(in: .whitespacesAndNewlines),
              !routeFile.isEmpty,
              let rawRegistration = request.routeRegistration else {
            return nil
        }
        let registration = rawRegistration.trimmingCharacters(in: .newlines)
        guard !registration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        guard request.allowRouteInsertion else {
            diagnostics.append(.init(
                severity: .blocker,
                code: .routeInsertionBlocked,
                message: "Route insertion requires explicit opt-in before writing \(routeFile)."))
            return nil
        }

        let resolvedRoute = resolveTarget(repoRoot: request.repoRoot, targetFile: routeFile)
        if !resolvedRoute.isInsideRepository {
            diagnostics.append(.init(
                severity: .blocker,
                code: .routeInsertionBlocked,
                message: "Route file must stay inside the selected repository: \(routeFile)"))
            return nil
        }
        if resolvedRoute.url.pathExtension.lowercased() != "swift" {
            diagnostics.append(.init(
                severity: .blocker,
                code: .routeInsertionBlocked,
                message: "Route insertion only supports Swift source files."))
            return nil
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: resolvedRoute.url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            diagnostics.append(.init(
                severity: .blocker,
                code: .routeInsertionBlocked,
                message: "Route insertion cannot write into a directory."))
            return nil
        }

        let sameAsTarget = resolvedRoute.url.path == targetURL.path
        let originalRouteSource: String
        if sameAsTarget {
            originalRouteSource = targetSourceAfterInjection
        } else if let source = try? String(contentsOf: resolvedRoute.url, encoding: .utf8) {
            originalRouteSource = source
        } else {
            diagnostics.append(.init(
                severity: .blocker,
                code: .routeFileMissing,
                message: "Route file is missing or unreadable: \(resolvedRoute.url.path)"))
            return nil
        }

        for finding in SourceSafety.inspect(source: originalRouteSource, fileName: resolvedRoute.url.lastPathComponent) {
            if finding.severity == .blocker {
                diagnostics.append(.init(severity: .blocker, code: .sourcePreflight, message: finding.message))
            }
        }

        guard let insertion = insertRouteRegistration(in: originalRouteSource, registration: registration) else {
            diagnostics.append(.init(
                severity: .blocker,
                code: .routeInsertionBlocked,
                message: "Route file must contain // VUA:BEGIN-ROUTES and // VUA:END-ROUTES markers."))
            return nil
        }

        if !insertion.inserted {
            diagnostics.append(.init(
                severity: .info,
                code: .routeAlreadyRegistered,
                message: "Route registration is already present; no duplicate route entry will be inserted."))
        }

        let routePreviewDiff = unifiedDiff(
            old: originalRouteSource,
            new: insertion.source,
            filePath: resolvedRoute.relativePath)
        return RoutePlan(
            url: resolvedRoute.url,
            relativePath: resolvedRoute.relativePath,
            originalSource: originalRouteSource,
            finalSource: insertion.source,
            routePreviewDiff: routePreviewDiff,
            inserted: insertion.inserted,
            isTargetFile: sameAsTarget)
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

    private static func insertRouteRegistration(in source: String, registration: String) -> (source: String, inserted: Bool)? {
        guard let start = source.range(of: "// VUA:BEGIN-ROUTES"),
              let end = source.range(of: "// VUA:END-ROUTES"),
              start.lowerBound < end.upperBound else { return nil }

        let routeRegion = String(source[start.upperBound..<end.lowerBound])
        let trimmedRegistration = registration.trimmingCharacters(in: .newlines)
        if routeRegion.contains(trimmedRegistration) {
            return (source, false)
        }

        let beforeEnd = String(source[..<end.lowerBound])
        let afterEnd = String(source[end.lowerBound...])
        let prefix = beforeEnd.hasSuffix("\n") ? "" : "\n"
        let suffix = trimmedRegistration.hasSuffix("\n") ? "" : "\n"
        return (beforeEnd + prefix + trimmedRegistration + suffix + afterEnd, true)
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
