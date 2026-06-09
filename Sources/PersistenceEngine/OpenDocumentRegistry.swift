import Foundation

/// Process-wide registry of currently-open `.vuaproj` URLs, so the app can warn
/// when the same document is about to be opened in a second window (which would
/// risk divergent edits / last-writer-wins saves).
public final class OpenDocumentRegistry: @unchecked Sendable {
    public static let shared = OpenDocumentRegistry()

    private let lock = NSLock()
    private var open: Set<String> = []

    public init() {}

    private func key(_ url: URL) -> String { url.standardizedFileURL.path }

    /// True if the URL is already registered as open.
    public func isOpen(_ url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return open.contains(key(url))
    }

    /// Registers a URL as open. Returns false if it was already open.
    @discardableResult
    public func register(_ url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return open.insert(key(url)).inserted
    }

    public func unregister(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        open.remove(key(url))
    }
}
