import Foundation

/// Most-recently-used document URLs, backed by `UserDefaults`. Persists across
/// launches so File ▸ Open Recent works and the app can auto-reopen the last
/// document. Local-first: nothing leaves the machine.
public final class RecentDocumentsStore: @unchecked Sendable {
    public static let lastOpenedKey = "vua.lastOpenedDocumentURL"
    public static let recentsKey = "vua.recentDocumentURLs"

    private let defaults: UserDefaults
    private let maxCount: Int

    public init(defaults: UserDefaults = .standard, maxCount: Int = 10) {
        self.defaults = defaults
        self.maxCount = maxCount
    }

    public var lastOpened: URL? {
        get { defaults.string(forKey: Self.lastOpenedKey).flatMap { URL(fileURLWithPath: $0) } }
        set { defaults.set(newValue?.path, forKey: Self.lastOpenedKey) }
    }

    public var recents: [URL] {
        let raw = defaults.stringArray(forKey: Self.recentsKey) ?? []
        return raw.map { URL(fileURLWithPath: $0) }
    }

    /// Records `url` as the most-recently-used document. Deduplicates and
    /// trims to `maxCount`. Stale entries (deleted files) are pruned lazily.
    public func record(_ url: URL) {
        let path = url.standardizedFileURL.path
        var paths = defaults.stringArray(forKey: Self.recentsKey) ?? []
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > maxCount { paths = Array(paths.prefix(maxCount)) }
        defaults.set(paths, forKey: Self.recentsKey)
        lastOpened = url
    }

    /// Returns the most-recent existing document URL (skips deleted ones).
    public func mostRecentExisting(using fm: FileManager = .default) -> URL? {
        for url in recents where fm.fileExists(atPath: url.path) { return url }
        return nil
    }

    public func clear() {
        defaults.removeObject(forKey: Self.recentsKey)
        defaults.removeObject(forKey: Self.lastOpenedKey)
    }
}
