import Foundation
import VUACore

/// Version snapshots stored inside a `.vuaproj` bundle (`Snapshots/`).
/// A lightweight "Time Machine" for UI edits: each save can drop a timestamped
/// copy of `document.json`, and the user can restore any of them.
public enum SnapshotStore {
    public static let directoryName = "Snapshots"

    public struct Info: Identifiable, Hashable, Sendable {
        public var id: String { fileName }
        public var fileName: String
        public var url: URL
        public var date: Date
    }

    public static func directory(in bundleURL: URL) -> URL {
        bundleURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Writes a snapshot of `document` into the bundle. `at` is injectable so
    /// the behaviour is deterministic under test. Returns the snapshot URL.
    @discardableResult
    public static func write(_ document: Document, into bundleURL: URL,
                             at date: Date = Date(), keeping maxCount: Int = 25) throws -> URL {
        let dir = directory(in: bundleURL)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Self.stampFormatter.string(from: date)
        let url = dir.appendingPathComponent("snapshot-\(stamp).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: url, options: [.atomic])
        prune(in: bundleURL, keeping: maxCount)
        return url
    }

    /// Lists snapshots newest-first.
    public static func list(in bundleURL: URL) -> [Info] {
        let dir = directory(in: bundleURL)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        let infos = urls.filter { $0.pathExtension == "json" }.compactMap { url -> Info? in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return Info(fileName: url.lastPathComponent, url: url, date: date)
        }
        return infos.sorted { $0.date > $1.date }
    }

    /// Decodes a snapshot file into a document.
    public static func read(_ url: URL) throws -> Document {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Document.self, from: data)
    }

    /// Keeps the newest `maxCount` snapshots, deleting older ones.
    public static func prune(in bundleURL: URL, keeping maxCount: Int) {
        let all = list(in: bundleURL)
        guard all.count > maxCount else { return }
        for info in all.dropFirst(maxCount) {
            try? FileManager.default.removeItem(at: info.url)
        }
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss-SSS"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}
