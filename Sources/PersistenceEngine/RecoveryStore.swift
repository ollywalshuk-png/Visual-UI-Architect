import Foundation
import VUACore

/// Autosave + crash recovery. The app periodically writes the live document to
/// a recovery file in Application Support. On the next launch, if a recovery
/// file exists (i.e. the previous session didn't exit cleanly), the app offers
/// to restore it. Local-first; nothing leaves the machine.
public final class RecoveryStore: @unchecked Sendable {
    private let directory: URL
    private let fm = FileManager.default

    /// Metadata sidecar describing the recovery payload.
    public struct Meta: Codable, Sendable {
        public var savedAt: Date
        public var originalPath: String?   // the .vuaproj this came from, if any
        public var documentName: String
        public init(savedAt: Date, originalPath: String?, documentName: String) {
            self.savedAt = savedAt
            self.originalPath = originalPath
            self.documentName = documentName
        }
    }

    public struct Recovered: Sendable {
        public var document: Document
        public var meta: Meta
        public var payloadURL: URL
        public var conflict: Conflict
    }

    /// How the recovered draft relates to the on-disk saved document.
    public enum Conflict: String, Sendable {
        case noSavedFile        // never saved, or original bundle is gone
        case recoveryNewer      // draft is newer than the last save (restore likely wanted)
        case recoveryOlder      // draft predates the last save (saved file is fresher)
        case sameAge

        public var message: String {
            switch self {
            case .noSavedFile: return "This draft was never saved to a project file."
            case .recoveryNewer: return "The recovered draft is newer than the last save."
            case .recoveryOlder: return "The last saved version is newer than this draft."
            case .sameAge: return "The recovered draft matches the last save time."
            }
        }
    }

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("VisualUIArchitect/Recovery", isDirectory: true)
        }
    }

    private var payloadURL: URL { directory.appendingPathComponent("autosave.json") }
    private var metaURL: URL { directory.appendingPathComponent("autosave.meta.json") }

    /// Writes/overwrites the recovery payload. Cheap enough to call on a timer.
    public func write(_ document: Document, originalPath: String?, at date: Date = Date()) throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(document).write(to: payloadURL, options: [.atomic])
        let meta = Meta(savedAt: date, originalPath: originalPath, documentName: document.name)
        try encoder.encode(meta).write(to: metaURL, options: [.atomic])
    }

    public var hasRecovery: Bool { fm.fileExists(atPath: payloadURL.path) }

    /// Loads the recovery payload, if present and decodable, classifying how it
    /// relates to the saved document it came from.
    public func load() -> Recovered? {
        guard let payload = try? Data(contentsOf: payloadURL),
              let document = try? JSONDecoder().decode(Document.self, from: payload),
              let metaData = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(Meta.self, from: metaData) else { return nil }
        return Recovered(document: document, meta: meta, payloadURL: payloadURL,
                         conflict: Self.classify(meta: meta))
    }

    /// Compares the draft's save time to the saved bundle's `document.json` mtime.
    public static func classify(meta: Meta, fileManager fm: FileManager = .default) -> Conflict {
        guard let path = meta.originalPath else { return .noSavedFile }
        let docURL = URL(fileURLWithPath: path).appendingPathComponent(VUABundle.documentFileName)
        guard fm.fileExists(atPath: docURL.path),
              let saved = try? docURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return .noSavedFile }
        let delta = meta.savedAt.timeIntervalSince(saved)
        if delta > 1 { return .recoveryNewer }
        if delta < -1 { return .recoveryOlder }
        return .sameAge
    }

    /// Clears recovery files — call after a clean save/close so the next launch
    /// doesn't offer a stale restore.
    public func clear() {
        try? fm.removeItem(at: payloadURL)
        try? fm.removeItem(at: metaURL)
    }
}
