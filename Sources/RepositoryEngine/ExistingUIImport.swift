import Foundation
import SwiftSyntax
import SwiftParser
import VUACore

/// User-facing "Import Existing UI" engine (Phase 18). Discovers SwiftUI views
/// in a file or repo, scores how completely each can be reconstructed, and
/// imports the chosen one into the editable layer model — all on top of the
/// existing `SwiftUIParser` (SwiftSyntax, no regex).
public enum ExistingUIImport {

    // MARK: - Candidate model

    public struct Candidate: Identifiable, Hashable, Sendable {
        public var id: String { "\(filePath)#\(viewName)" }
        public var viewName: String
        public var filePath: String
        /// Repository root the file belongs to (best-effort).
        public var repoRoot: String?
        /// 0…1 — fraction of recognised view expressions over total.
        public var confidence: Double
        public var supportedElementCount: Int
        public var unsupportedElementCount: Int
        public var hasAnchors: Bool
        public var isPreviewOnly: Bool
        public var warnings: [String]

        public init(viewName: String, filePath: String, repoRoot: String? = nil,
                    confidence: Double, supportedElementCount: Int,
                    unsupportedElementCount: Int, hasAnchors: Bool,
                    isPreviewOnly: Bool, warnings: [String]) {
            self.viewName = viewName
            self.filePath = filePath
            self.repoRoot = repoRoot
            self.confidence = confidence
            self.supportedElementCount = supportedElementCount
            self.unsupportedElementCount = unsupportedElementCount
            self.hasAnchors = hasAnchors
            self.isPreviewOnly = isPreviewOnly
            self.warnings = warnings
        }
    }

    /// Set of SwiftUI primitives the parser reconstructs on this first pass.
    static let supportedViews: Set<String> = [
        "ZStack", "VStack", "HStack", "Group",
        "Text", "Button", "Image", "Label",
        "Rectangle", "RoundedRectangle", "Circle", "Ellipse", "Capsule", "Divider",
        "Slider", "Toggle", "Spacer"
    ]

    // MARK: - Scan a single file

    /// Returns one candidate per `View` struct found in a source string.
    public static func candidates(inSource source: String, filePath: String, repoRoot: String? = nil) -> [Candidate] {
        let tree = Parser.parse(source: source)
        let finder = ViewStructScanner(viewMode: .sourceAccurate)
        finder.walk(tree)
        return finder.views.map { v in
            let total = v.supported + v.unsupported
            let confidence = total == 0 ? 0 : Double(v.supported) / Double(total)
            var warnings: [String] = []
            if v.unsupported > 0 {
                warnings.append("\(v.unsupported) unsupported element(s) will import as locked placeholders.")
            }
            if !v.hasAnchors {
                warnings.append("No accessibilityIdentifier anchors — round-trip editing needs anchors.")
            }
            if v.isPreviewOnly {
                warnings.append("This view appears to be a #Preview-only / PreviewProvider helper.")
            }
            return Candidate(
                viewName: v.name, filePath: filePath, repoRoot: repoRoot,
                confidence: confidence,
                supportedElementCount: v.supported,
                unsupportedElementCount: v.unsupported,
                hasAnchors: v.hasAnchors,
                isPreviewOnly: v.isPreviewOnly,
                warnings: warnings)
        }
    }

    /// Convenience: scan a file URL.
    public static func candidates(inFile url: URL, repoRoot: URL? = nil) -> [Candidate] {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return candidates(inSource: source, filePath: url.path, repoRoot: repoRoot?.path)
    }

    // MARK: - Scan a repo

    /// Scans a repository directory for SwiftUI view candidates, preferring the
    /// usual UI locations but covering all `.swift` files. Skips noise dirs.
    public static func scanRepository(_ root: URL) -> [Candidate] {
        let fm = FileManager.default
        let skip: Set<String> = [".git", ".build", ".swiftpm", "DerivedData", "Pods", "node_modules"]
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var out: [Candidate] = []
        for case let url as URL in en {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                if skip.contains(url.lastPathComponent) { en.skipDescendants() }
                continue
            }
            guard url.pathExtension == "swift" else { continue }
            // Cheap pre-filter so we don't full-parse every Swift file.
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  text.contains(": View") || text.contains(":View") else { continue }
            out.append(contentsOf: candidates(inSource: text, filePath: url.path, repoRoot: root.path))
        }
        return out.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Project detection

    public struct ProjectInfo: Sendable {
        public var hasPackageSwift: Bool
        public var xcodeProjects: [String]
        public var xcworkspaces: [String]
        public var uiDirectories: [String]   // Sources/Views/UI/Components present
    }

    /// Lightweight detection of project shape under a root (one level deep for
    /// projects/workspaces, plus the conventional UI folders).
    public static func detectProject(_ root: URL) -> ProjectInfo {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let projects = entries.filter { $0.pathExtension == "xcodeproj" }.map { $0.lastPathComponent }
        let workspaces = entries.filter { $0.pathExtension == "xcworkspace" }.map { $0.lastPathComponent }
        let uiNames = ["Sources", "Views", "UI", "Components"]
        let uiDirs = uiNames.filter { name in
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: root.appendingPathComponent(name).path, isDirectory: &isDir) && isDir.boolValue
        }
        return ProjectInfo(
            hasPackageSwift: fm.fileExists(atPath: root.appendingPathComponent("Package.swift").path),
            xcodeProjects: projects, xcworkspaces: workspaces, uiDirectories: uiDirs)
    }

    // MARK: - Import

    public struct Imported: Sendable {
        public var view: ParsedView
        public var sourceHash: String
        public var hasAnchors: Bool
        public var anchorsInjected: Bool = false

        public init(view: ParsedView, sourceHash: String, hasAnchors: Bool, anchorsInjected: Bool = false) {
            self.view = view
            self.sourceHash = sourceHash
            self.hasAnchors = hasAnchors
            self.anchorsInjected = anchorsInjected
        }
    }

    /// Parses the candidate's view into editable layers and computes a content
    /// hash of the source for change-detection at apply time.
    public static func importCandidate(_ candidate: Candidate) -> Imported? {
        let url = URL(fileURLWithPath: candidate.filePath)
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let parsed = SwiftUIParser().parse(source: source, filePath: candidate.filePath)
        guard let view = parsed.first(where: { $0.typeName == candidate.viewName }) ?? parsed.first else { return nil }
        return Imported(
            view: view,
            sourceHash: sourceHash(source),
            hasAnchors: candidate.hasAnchors)
    }

    /// Adds stable accessibility anchors to common SwiftUI view constructor
    /// lines when a candidate has none, then reparses the file. This is a
    /// pragmatic source instrumentation step: unsupported/custom code is left
    /// untouched, existing formatting/comments are preserved, and anchors make
    /// later partial apply safe instead of temporary-only.
    public static func importCandidateEnsuringAnchors(_ candidate: Candidate) -> Imported? {
        if candidate.hasAnchors { return importCandidate(candidate) }
        guard injectAnchors(intoFile: candidate.filePath, viewName: candidate.viewName) else {
            return importCandidate(candidate)
        }
        let refreshed = candidates(inFile: URL(fileURLWithPath: candidate.filePath))
            .first { $0.viewName == candidate.viewName } ?? candidate
        guard var imported = importCandidate(refreshed) else { return nil }
        imported.anchorsInjected = true
        imported.hasAnchors = true
        return imported
    }

    @discardableResult
    public static func injectAnchors(intoFile path: String, viewName: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard let source = try? String(contentsOf: url, encoding: .utf8),
              !source.contains(".accessibilityIdentifier(") else { return false }
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        var inTarget = false
        var braceDepth = 0
        var counter = 0
        let constructors = ["Text(", "Button(", "Image(", "Toggle(", "Slider(", "TextField(", "Picker(", "Label(", "Rectangle(", "RoundedRectangle(", "Circle(", "Capsule(", "VStack", "HStack", "ZStack", "List", "Form", "Section"]
        for line in lines {
            if line.contains("struct \(viewName):") { inTarget = true }
            output.append(line)
            if inTarget, constructors.contains(where: { line.trimmingCharacters(in: .whitespaces).hasPrefix($0) }),
               !line.contains(".accessibilityIdentifier") {
                let indent = String(line.prefix { $0 == " " || $0 == "\t" })
                output.append("\(indent)    .accessibilityIdentifier(\"vua_\(viewName)_\(counter)\")")
                counter += 1
            }
            if inTarget {
                braceDepth += line.filter { $0 == "{" }.count
                braceDepth -= line.filter { $0 == "}" }.count
                if braceDepth <= 0, line.contains("}") { inTarget = false }
            }
        }
        guard counter > 0 else { return false }
        let updated = output.joined(separator: source.contains("\r\n") ? "\r\n" : "\n")
        do {
            try updated.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    /// Stable content hash (FNV-1a, 64-bit) — deterministic and dependency-free,
    /// so the same source always yields the same hash for change detection.
    public static func sourceHash(_ source: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in source.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    /// True when the file on disk no longer matches the hash captured at import.
    public static func sourceChanged(at path: String, since hash: String) -> Bool {
        guard let current = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else {
            return true // missing/unreadable counts as "changed" (blocks apply)
        }
        return sourceHash(current) != hash
    }
}

// MARK: - Syntax scanner (counts supported vs unsupported view calls)

private final class ViewStructScanner: SyntaxVisitor {
    struct Found { var name: String; var supported: Int; var unsupported: Int; var hasAnchors: Bool; var isPreviewOnly: Bool }
    private(set) var views: [Found] = []

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let inheritance = node.inheritanceClause,
              inheritance.inheritedTypes.contains(where: {
                  $0.type.as(IdentifierTypeSyntax.self)?.name.text == "View"
              }) else {
            return .visitChildren
        }
        // Find the `body` accessor and count view calls within it.
        let counter = ViewCallCounter(viewMode: .sourceAccurate)
        if let body = SwiftUIParser.bodyExpression(of: node) {
            counter.walk(Syntax(body))
        }
        let isPreviewOnly = node.name.text.contains("Preview")
            || (counter.supported + counter.unsupported == 0)
        views.append(Found(
            name: node.name.text,
            supported: counter.supported,
            unsupported: counter.unsupported,
            hasAnchors: counter.hasAnchors,
            isPreviewOnly: isPreviewOnly))
        return .visitChildren
    }
}

private final class ViewCallCounter: SyntaxVisitor {
    private(set) var supported = 0
    private(set) var unsupported = 0
    private(set) var hasAnchors = false

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let callee = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            let name = callee.baseName.text
            // Only count things that look like view constructors (capitalised).
            if let first = name.first, first.isUppercase {
                if ExistingUIImport.supportedViews.contains(name) { supported += 1 }
                else { unsupported += 1 }
            }
        } else if let member = node.calledExpression.as(MemberAccessExprSyntax.self),
                  member.declName.baseName.text == "accessibilityIdentifier" {
            hasAnchors = true
        }
        return .visitChildren
    }
}
