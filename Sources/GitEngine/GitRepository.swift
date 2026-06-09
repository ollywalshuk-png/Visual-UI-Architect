import Foundation

/// High-level, intention-revealing git operations for the version-control UI.
public struct GitRepository: Sendable {
    public let runner: GitRunner

    public init(repositoryURL: URL) {
        self.runner = GitRunner(repositoryURL: repositoryURL)
    }

    public var url: URL { runner.repositoryURL }

    public struct FileStatus: Identifiable, Hashable, Sendable {
        public var id: String { path }
        public var path: String
        public var index: Character   // staged state
        public var worktree: Character // unstaged state
        public var isUntracked: Bool { index == "?" && worktree == "?" }
    }

    public struct Commit: Identifiable, Hashable, Sendable {
        public var id: String { hash }
        public var hash: String
        public var author: String
        public var date: String
        public var subject: String
    }

    public func isGitRepository() -> Bool {
        (try? runner.run(["rev-parse", "--is-inside-work-tree"]))?.ok ?? false
    }

    public func currentBranch() throws -> String {
        try runner.runChecked(["rev-parse", "--abbrev-ref", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parses `git status --porcelain` into structured entries.
    public func status() throws -> [FileStatus] {
        let out = try runner.runChecked(["status", "--porcelain"])
        return out.split(separator: "\n").compactMap { line in
            guard line.count >= 3 else { return nil }
            let chars = Array(line)
            let path = String(chars[3...])
            return FileStatus(path: path, index: chars[0], worktree: chars[1])
        }
    }

    public func diff(path: String? = nil, staged: Bool = false) throws -> String {
        var args = ["diff"]
        if staged { args.append("--staged") }
        if let path { args.append("--"); args.append(path) }
        return try runner.runChecked(args)
    }

    public func stage(_ paths: [String]) throws {
        try runner.runChecked(["add"] + paths)
    }

    public func commit(message: String) throws {
        try runner.runChecked(["commit", "-m", message])
    }

    public func createBranch(_ name: String, checkout: Bool = true) throws {
        try runner.runChecked(checkout ? ["checkout", "-b", name] : ["branch", name])
    }

    /// Discards working-tree changes for the given paths (rollback).
    public func restore(_ paths: [String]) throws {
        try runner.runChecked(["restore"] + paths)
    }

    public func revertToCommit(_ hash: String, paths: [String]) throws {
        try runner.runChecked(["checkout", hash, "--"] + paths)
    }

    public func log(limit: Int = 50) throws -> [Commit] {
        let sep = "\u{1f}"
        let fmt = ["%H", "%an", "%ad", "%s"].joined(separator: sep)
        let out = try runner.runChecked(["log", "-n", String(limit), "--date=short", "--pretty=format:\(fmt)"])
        return out.split(separator: "\n").compactMap { line in
            let parts = line.components(separatedBy: sep)
            guard parts.count == 4 else { return nil }
            return Commit(hash: parts[0], author: parts[1], date: parts[2], subject: parts[3])
        }
    }
}
