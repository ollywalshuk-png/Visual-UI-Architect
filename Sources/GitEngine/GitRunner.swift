import Foundation

/// Thin wrapper that shells out to the system `git`. Local-first: no network
/// calls are made unless the caller explicitly invokes push/pull/clone.
public struct GitRunner: Sendable {
    public let repositoryURL: URL

    public init(repositoryURL: URL) {
        self.repositoryURL = repositoryURL
    }

    public struct Output: Sendable {
        public var status: Int32
        public var stdout: String
        public var stderr: String
        public var ok: Bool { status == 0 }
    }

    public enum GitError: Error, CustomStringConvertible {
        case gitUnavailable
        case command(args: [String], stderr: String, status: Int32)

        public var description: String {
            switch self {
            case .gitUnavailable: return "git executable not found."
            case .command(let args, let stderr, let status):
                return "git \(args.joined(separator: " ")) failed (\(status)): \(stderr)"
            }
        }
    }

    /// Runs git with the given arguments inside the repository directory.
    @discardableResult
    public func run(_ args: [String]) throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = repositoryURL

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw GitError.gitUnavailable
        }
        process.waitUntilExit()

        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return Output(status: process.terminationStatus, stdout: out, stderr: err)
    }

    /// Runs git and throws unless it exits 0.
    @discardableResult
    public func runChecked(_ args: [String]) throws -> String {
        let result = try run(args)
        guard result.ok else {
            throw GitError.command(args: args, stderr: result.stderr, status: result.status)
        }
        return result.stdout
    }
}
