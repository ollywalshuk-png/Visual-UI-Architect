import Foundation
import CryptoKit

/// Pre-write safety checks on a source file: merge-conflict markers,
/// permissions, external modification (hash drift), line-ending and
/// indentation fingerprints, and anchor sanity. Run before every
/// Apply-to-Source so the writer never lands a patch on a file in a state
/// the parse never saw.
public struct SourcePreflight: Sendable {

    public struct Finding: Hashable, Sendable, Identifiable {
        public enum Severity: Int, Comparable, Sendable {
            case info, warning, blocker
            public static func < (l: Severity, r: Severity) -> Bool { l.rawValue < r.rawValue }
        }
        public enum Code: String, Sendable {
            case fileMissing
            case notReadable
            case notWritable
            case mergeConflictMarkers
            case externallyModified
            case crlfLineEndings
            case tabIndentation
            case duplicateAnchors
            case missingAnchor
            case unsupportedRegion
            case missingLineAnchor
        }
        public let id = UUID()
        public var severity: Severity
        public var code: Code
        public var message: String
    }

    public var findings: [Finding]
    public var sourceHash: String?

    public var hasBlocker: Bool { findings.contains { $0.severity == .blocker } }
    /// True when the file uses CRLF line endings — the writer must preserve them.
    public var usesCRLF: Bool { findings.contains { $0.code == .crlfLineEndings } }
}

public struct SourceSafety: Sendable {
    public init() {}

    /// SHA-256 of the source text — recorded at parse time and compared at
    /// apply time to catch external edits between the two.
    public static func hash(of source: String) -> String {
        SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Inspects a file (and optionally the hash recorded when it was parsed,
    /// plus the anchors the apply expects to find) before any write.
    public func preflight(fileURL: URL,
                          expectedHash: String? = nil,
                          expectedAnchors: [String] = []) -> SourcePreflight {
        let fm = FileManager.default
        var findings: [SourcePreflight.Finding] = []

        guard fm.fileExists(atPath: fileURL.path) else {
            return SourcePreflight(findings: [.init(
                severity: .blocker, code: .fileMissing,
                message: "Source file no longer exists: \(fileURL.lastPathComponent) — it may have been moved or deleted since the parse.")],
                sourceHash: nil)
        }
        guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return SourcePreflight(findings: [.init(
                severity: .blocker, code: .notReadable,
                message: "Source file could not be read (permissions or encoding): \(fileURL.lastPathComponent).")],
                sourceHash: nil)
        }

        if !fm.isWritableFile(atPath: fileURL.path) {
            findings.append(.init(
                severity: .blocker, code: .notWritable,
                message: "\(fileURL.lastPathComponent) is read-only — Apply would fail mid-write."))
        }

        findings.append(contentsOf: Self.inspect(source: source,
                                                 fileName: fileURL.lastPathComponent,
                                                 expectedHash: expectedHash,
                                                 expectedAnchors: expectedAnchors))
        return SourcePreflight(findings: findings, sourceHash: Self.hash(of: source))
    }

    /// The pure-text part of preflight — separated so it's directly testable.
    public static func inspect(source: String,
                               fileName: String,
                               expectedHash: String? = nil,
                               expectedAnchors: [String] = []) -> [SourcePreflight.Finding] {
        var findings: [SourcePreflight.Finding] = []

        // Merge-conflict markers: writing through them corrupts the file.
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let hasConflict = lines.contains {
            $0.hasPrefix("<<<<<<< ") || $0.hasPrefix(">>>>>>> ") || $0 == "=======" || $0.hasPrefix("||||||| ")
        }
        if hasConflict {
            findings.append(.init(
                severity: .blocker, code: .mergeConflictMarkers,
                message: "\(fileName) contains unresolved merge-conflict markers — resolve the conflict before applying."))
        }

        // External modification since parse.
        if let expected = expectedHash, hash(of: source) != expected {
            findings.append(.init(
                severity: .blocker, code: .externallyModified,
                message: "\(fileName) changed on disk after it was parsed — re-open it so the canvas reflects the current source."))
        }

        // Formatting fingerprints — preserved, but surfaced so changes in the
        // diff are explainable.
        if source.contains("\r\n") {
            findings.append(.init(
                severity: .info, code: .crlfLineEndings,
                message: "\(fileName) uses CRLF line endings — they are preserved on write."))
        }
        if lines.contains(where: { $0.hasPrefix("\t") }) {
            findings.append(.init(
                severity: .info, code: .tabIndentation,
                message: "\(fileName) uses tab indentation — it is preserved on write."))
        }

        // Anchor sanity: every anchor the apply targets must exist exactly once.
        if !expectedAnchors.isEmpty {
            let counts = anchorCounts(in: source)
            for anchor in expectedAnchors {
                let n = counts[anchor] ?? 0
                if n == 0 {
                    findings.append(.init(
                        severity: .blocker, code: .missingAnchor,
                        message: "Anchor “\(anchor)” was not found in \(fileName) — the bound layer can no longer be patched."))
                } else if n > 1 {
                    findings.append(.init(
                        severity: .blocker, code: .duplicateAnchors,
                        message: "Anchor “\(anchor)” appears \(n)× in \(fileName) — the patch target is ambiguous."))
                }
            }
        }

        for region in unsupportedRegions(in: source) {
            findings.append(.init(
                severity: .warning, code: .unsupportedRegion,
                message: "\(fileName) contains unsupported SwiftUI region '\(region)' — it will be preserved and left untouched."))
        }

        return findings
    }

    /// Occurrences of each `.accessibilityIdentifier("…")` literal. Line-shaped
    /// scan for diagnostics only — structural editing stays in SwiftSyntax.
    public static func anchorCounts(in source: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        let marker = ".accessibilityIdentifier(\""
        var search = source.startIndex
        while let r = source.range(of: marker, range: search..<source.endIndex) {
            let rest = source[r.upperBound...]
            if let close = rest.firstIndex(of: "\"") {
                counts[String(rest[..<close]), default: 0] += 1
                search = close
            } else {
                break
            }
        }
        return counts
    }

    /// Developer-marked or importer-marked regions that the round-trip writer
    /// must preserve exactly. Structural editing remains SwiftSyntax-based; this
    /// line scan only surfaces diagnostics to the user.
    public static func unsupportedRegions(in source: String) -> [String] {
        let markers = ["VUA_UNSUPPORTED", "vua:unsupported", "UnsupportedSwiftUI"]
        var regions: [String] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            guard markers.contains(where: { line.contains($0) }) else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !regions.contains(trimmed) { regions.append(trimmed) }
        }
        return regions
    }

    public static func lineNumber(of anchor: String, in source: String) -> Int? {
        let marker = ".accessibilityIdentifier(\"\(anchor)\")"
        guard let range = source.range(of: marker) else { return nil }
        return source[..<range.lowerBound].reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }
}
