import Foundation
import VUACore

public struct RepositoryGraphIndex: Sendable, Hashable {
    public var repoRoot: URL
    public var fileFingerprints: [String: Date]
    public var graph: ExistingAppViewGraph
    public var builtAt: Date

    public init(repoRoot: URL, files: [RepositoryFile], document: Document? = nil, builtAt: Date = Date()) {
        self.repoRoot = repoRoot
        self.fileFingerprints = Self.fingerprints(files)
        self.graph = ExistingAppViewGraphBuilder.build(repoRoot: repoRoot, files: files, document: document)
        self.builtAt = builtAt
    }

    public func isFresh(for files: [RepositoryFile]) -> Bool {
        fileFingerprints == Self.fingerprints(files)
    }

    private static func fingerprints(_ files: [RepositoryFile]) -> [String: Date] {
        var out: [String: Date] = [:]
        for file in files {
            let url = URL(fileURLWithPath: file.absolutePath)
            out[file.absolutePath] = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return out
    }
}
