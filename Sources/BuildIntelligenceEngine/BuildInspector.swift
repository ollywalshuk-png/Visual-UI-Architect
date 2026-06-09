import Foundation

/// Probes the toolchain and package state, formats build commands, scans
/// generated source for build-breaking patterns, and translates raw build
/// failures into human explanations. Pure inspection — never mutates.
public struct BuildInspector {

    public init() {}

    // MARK: Toolchain

    /// Detects the active Swift toolchain. CLT-only machines (no full Xcode)
    /// cannot run xcodebuild/XCTest and choke on the #Preview macro.
    public func detectToolchain() -> ToolchainInfo {
        let version = Self.run("/usr/bin/env", ["swift", "--version"])
        let devDir = Self.run("/usr/bin/xcode-select", ["-p"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fullXcode = devDir?.contains(".app/Contents/Developer") ?? false
        return ToolchainInfo(
            swiftVersionLine: version?.split(separator: "\n").first.map(String.init),
            developerDir: devDir,
            hasFullXcode: fullXcode)
    }

    // MARK: Command formatting

    /// The exact SwiftPM invocation for a build kind/product — shown to the
    /// user so every build is repeatable in a terminal.
    public static func buildCommand(kind: BuildKind, product: String? = nil) -> [String] {
        var cmd = ["swift", "build", "-c", kind.configuration]
        if let product { cmd += ["--product", product] }
        return cmd
    }

    // MARK: Package / context inspection

    /// Builds a `BuildContext` for a package directory: locates the manifest
    /// and lockfile, checks staleness, and records toolchain caveats.
    public func makeContext(root: URL,
                            kind: BuildKind = .localDevelopment,
                            product: String? = nil,
                            toolchain: ToolchainInfo? = nil) -> BuildContext {
        let fm = FileManager.default
        var diagnostics: [BuildDiagnostic] = []
        let tc = toolchain ?? detectToolchain()

        let manifest = root.appendingPathComponent("Package.swift")
        let hasManifest = fm.fileExists(atPath: manifest.path)
        if !hasManifest {
            diagnostics.append(BuildDiagnostic(
                severity: .error, code: .missingPackageManifest,
                message: "No Package.swift found in \(root.lastPathComponent) — SwiftPM cannot build here.",
                suggestion: "Select the package root (the folder containing Package.swift)."))
        }

        let resolved = root.appendingPathComponent("Package.resolved")
        let hasResolved = fm.fileExists(atPath: resolved.path)
        if hasManifest {
            if !hasResolved {
                diagnostics.append(BuildDiagnostic(
                    severity: .info, code: .packageResolvedMissing,
                    message: "Package.resolved is missing — dependencies will be re-resolved (network may be required).",
                    suggestion: "Run `swift package resolve` once and commit Package.resolved for repeatable builds."))
            } else if let mDate = Self.modificationDate(manifest),
                      let rDate = Self.modificationDate(resolved),
                      mDate > rDate {
                diagnostics.append(BuildDiagnostic(
                    severity: .warning, code: .packageResolvedStale,
                    message: "Package.swift is newer than Package.resolved — the dependency graph may have drifted.",
                    suggestion: "Run `swift package resolve` to refresh the lockfile."))
            }
        }

        let buildDir = root.appendingPathComponent(".build")
        let hasCache = fm.fileExists(atPath: buildDir.path)

        if tc.commandLineToolsOnly {
            diagnostics.append(BuildDiagnostic(
                severity: .info, code: .commandLineToolsOnly,
                message: "Only Command Line Tools detected (no full Xcode) — xcodebuild, XCTest and #Preview are unavailable.",
                suggestion: "Use `swift build` + VUACheck locally; run XCTest in CI or on a machine with Xcode."))
        }

        return BuildContext(
            kind: kind,
            workingDirectory: root,
            product: product,
            toolchain: tc,
            packageManifest: hasManifest ? manifest : nil,
            packageResolved: hasResolved ? resolved : nil,
            hasBuildCache: hasCache,
            command: Self.buildCommand(kind: kind, product: product),
            diagnostics: diagnostics)
    }

    // MARK: Generated-source scanning

    /// Scans generated Swift source for imports that won't resolve in the
    /// target, a VUAControls dependency that isn't being bundled, and the
    /// #Preview macro on CLT-only machines. Line-shaped checks only — full
    /// SwiftUI structure parsing stays in SwiftSyntax (RepositoryEngine).
    public func scanGeneratedSource(_ source: String,
                                    knownModules: Set<String>,
                                    bundlesVUAControls: Bool,
                                    toolchain: ToolchainInfo) -> [BuildDiagnostic] {
        var diagnostics: [BuildDiagnostic] = []
        var imports: [String] = []
        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("import ") else { continue }
            let module = line.dropFirst("import ".count)
                .split(separator: " ").first.map(String.init) ?? ""
            if !module.isEmpty { imports.append(module) }
        }

        let alwaysAvailable: Set<String> = ["SwiftUI", "Foundation", "AppKit", "UIKit", "Combine", "Observation", "OSLog"]
        for module in imports {
            if module == "VUAControls" {
                if !bundlesVUAControls {
                    diagnostics.append(BuildDiagnostic(
                        severity: .error, code: .missingVUAControls,
                        message: "Generated code imports VUAControls but the export does not bundle it — the target build will fail with 'no such module'.",
                        suggestion: "Enable “Bundle VUAControls” in the export panel, or add VUAControls to the target package."))
                }
                continue
            }
            if !alwaysAvailable.contains(module) && !knownModules.contains(module) {
                diagnostics.append(BuildDiagnostic(
                    severity: .warning, code: .invalidGeneratedImport,
                    message: "Generated code imports “\(module)”, which is not a known module of the target.",
                    suggestion: "Add the module as a dependency or remove the import."))
            }
        }

        if source.contains("#Preview") && toolchain.commandLineToolsOnly {
            diagnostics.append(BuildDiagnostic(
                severity: .warning, code: .previewMacroCLTIncompatible,
                message: "Source uses the #Preview macro, which fails to expand with Command Line Tools only.",
                suggestion: "Strip #Preview blocks from exported code (VUA's exporter already omits them)."))
        }

        return diagnostics
    }

    // MARK: Failure explanation

    /// Translates raw `swift build` output into a one-paragraph human
    /// explanation of what went wrong and what to do about it.
    public static func explainFailure(_ output: String) -> String? {
        let lower = output.lowercased()

        if let r = lower.range(of: "no such module '") {
            let tail = lower[r.upperBound...]
            let module = tail.prefix(while: { $0 != "'" })
            return "A module named ‘\(module)’ could not be found. The target package doesn't declare it as a dependency — add it to Package.swift (or bundle it, if it's VUAControls) and build again."
        }
        if lower.contains("the manifest is invalid") || lower.contains("manifest parse error") {
            return "Package.swift itself failed to parse — the build never started. Check the manifest for syntax errors (a missing comma or bracket is the usual cause)."
        }
        if lower.contains("dependency") && (lower.contains("fetch") || lower.contains("failed to clone")) {
            return "A dependency could not be fetched. This usually means no network access, a moved/deleted upstream repository, or a stale Package.resolved — run `swift package resolve` when online."
        }
        if lower.contains("error: cannot find ") {
            return "The compiler found a reference to a symbol that doesn't exist in scope — usually a typo, a missing file in the target, or generated code referencing something that wasn't exported with it."
        }
        if lower.contains("undefined symbol") {
            return "Linking failed: a symbol was declared but never compiled into the build. A source file is probably missing from the target, or two targets disagree about a type."
        }
        if lower.contains("#preview") || lower.contains("previewmacro") {
            return "The #Preview macro failed to expand — expected on machines with Command Line Tools only. Remove #Preview blocks (VUA's exporter already does) or build with full Xcode."
        }
        if lower.contains("xcodebuild") && lower.contains("requires xcode") {
            return "xcodebuild needs full Xcode, but only Command Line Tools are installed. Use `swift build` (SwiftPM) instead."
        }
        if lower.contains("is not a member type") || lower.contains("ambiguous for type lookup") {
            return "A type name is ambiguous or wrongly qualified — commonly a SwiftUI name collision (e.g. a custom Alignment/Shape/Path vs SwiftUI's). Fully qualify one of them."
        }
        if lower.contains("error:") {
            return "The build failed with a compile error — open the first `error:` line below for the exact file and line; everything after the first error may be a cascade."
        }
        return nil
    }

    // MARK: Helpers

    private static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Runs a short-lived process and returns stdout, or nil on any failure.
    private static func run(_ launchPath: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
