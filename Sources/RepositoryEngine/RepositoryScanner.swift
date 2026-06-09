import Foundation
import SwiftSyntax
import SwiftParser
import VUACore

/// A file discovered while scanning a repository.
public struct RepositoryFile: Identifiable, Hashable, Sendable {
    public enum Role: String, Sendable { case swiftUIView, swiftSource, asset, other }
    public var id: String { relativePath }
    public var relativePath: String
    public var absolutePath: String
    public var role: Role
    /// View type names found in a SwiftUI source file.
    public var viewNames: [String]
}

/// Scans a repository directory for Swift sources (classifying SwiftUI view
/// files) and assets. Read-only and sandbox-respecting.
public struct RepositoryScanner {
    public let root: URL

    private static let assetExtensions: Set<String> = ["png", "jpg", "jpeg", "svg", "pdf"]
    private static let skippedDirectories: Set<String> = [".git", ".build", ".swiftpm", "DerivedData", "Pods", "node_modules"]

    public init(root: URL) { self.root = root }

    public func scan() -> [RepositoryFile] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var files: [RepositoryFile] = []
        for case let url as URL in enumerator {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                if Self.skippedDirectories.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            let rel = relativePath(of: url)
            let ext = url.pathExtension.lowercased()
            if ext == "swift" {
                let names = viewNames(in: url)
                files.append(RepositoryFile(
                    relativePath: rel, absolutePath: url.path,
                    role: names.isEmpty ? .swiftSource : .swiftUIView,
                    viewNames: names))
            } else if Self.assetExtensions.contains(ext) {
                files.append(RepositoryFile(
                    relativePath: rel, absolutePath: url.path, role: .asset, viewNames: []))
            }
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }

    private func relativePath(of url: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(rootPath) {
            return String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return url.lastPathComponent
    }

    /// Returns the names of `View` structs declared in a Swift file (cheap parse).
    private func viewNames(in url: URL) -> [String] {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        // Avoid full parse cost for files that clearly contain no views.
        guard source.contains(": View") || source.contains(":View") else { return [] }
        let tree = Parser.parse(source: source)
        let finder = ViewFinder(viewMode: .sourceAccurate)
        finder.walk(tree)
        return finder.viewStructs.map { $0.name.text }
    }
}
