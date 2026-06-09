import Foundation
import VUACore

/// `.vuaproj` document bundle — a directory package the user sees as one item.
///
///   MyProject.vuaproj/
///     document.json     // the serialised Document
///     Assets/           // every referenced asset, by `Asset.path`
///
/// Self-contained: moving the bundle to another machine moves the layout *and*
/// every imported image. The asset resolver pulls images from `Assets/` inside
/// the bundle whenever a document is open.
public enum VUABundle {
    public static let fileExtension = "vuaproj"
    public static let documentFileName = "document.json"
    public static let assetsDirectoryName = "Assets"

    public enum BundleError: Error, CustomStringConvertible {
        case wrongExtension(URL)
        case notADirectory(URL)
        case missingDocument(URL)
        case readFailed(URL, String)
        case writeFailed(URL, String)
        case unsupportedSchema(Int)

        public var description: String {
            switch self {
            case .wrongExtension(let url):
                return "Not a .\(VUABundle.fileExtension) bundle: \(url.lastPathComponent)"
            case .notADirectory(let url):
                return "Bundle path is not a directory: \(url.path)"
            case .missingDocument(let url):
                return "Bundle is missing \(VUABundle.documentFileName): \(url.lastPathComponent)"
            case .readFailed(let url, let why):
                return "Could not read \(url.lastPathComponent): \(why)"
            case .writeFailed(let url, let why):
                return "Could not write \(url.lastPathComponent): \(why)"
            case .unsupportedSchema(let v):
                return "Document schema v\(v) is newer than this build can read."
            }
        }
    }

    // MARK: - Layout helpers

    /// `Assets/` directory inside a bundle URL.
    public static func assetsDirectory(in bundleURL: URL) -> URL {
        bundleURL.appendingPathComponent(assetsDirectoryName, isDirectory: true)
    }

    /// `document.json` URL inside a bundle URL.
    public static func documentFile(in bundleURL: URL) -> URL {
        bundleURL.appendingPathComponent(documentFileName)
    }

    // MARK: - Read

    /// Reads a document bundle. Mutates only what the caller does with the
    /// returned value — does not touch the filesystem.
    public static func read(from bundleURL: URL) throws -> Document {
        guard bundleURL.pathExtension == fileExtension else { throw BundleError.wrongExtension(bundleURL) }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: bundleURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw BundleError.notADirectory(bundleURL)
        }
        let docURL = documentFile(in: bundleURL)
        guard FileManager.default.fileExists(atPath: docURL.path) else {
            throw BundleError.missingDocument(bundleURL)
        }
        do {
            let data = try Data(contentsOf: docURL)
            let document = try JSONDecoder().decode(Document.self, from: data)
            guard document.schemaVersion <= Document.currentSchemaVersion else {
                throw BundleError.unsupportedSchema(document.schemaVersion)
            }
            return document
        } catch let err as BundleError {
            throw err
        } catch {
            throw BundleError.readFailed(docURL, error.localizedDescription)
        }
    }

    /// Non-throwing diagnosis: returns nil if the bundle reads cleanly, or a
    /// human-readable reason if it's missing/corrupt. Used by the open flow to
    /// warn rather than crash on a damaged `.vuaproj`.
    public static func diagnose(_ bundleURL: URL) -> String? {
        do { _ = try read(from: bundleURL); return nil }
        catch let error as BundleError { return error.description }
        catch { return "Unreadable document: \(error.localizedDescription)" }
    }

    // MARK: - Write

    /// Writes a document to a bundle URL. When `copyingAssetsFrom` is provided,
    /// every referenced asset is copied into the bundle's `Assets/` directory
    /// (this is the typical case: the imported files live in Application
    /// Support and we want a self-contained bundle).
    ///
    /// Existing bundle contents are preserved; only changed files are
    /// overwritten. Returns the list of asset filenames now present.
    @discardableResult
    public static func write(
        _ document: Document,
        to bundleURL: URL,
        copyingAssetsFrom sourceAssetsDirectory: URL?
    ) throws -> [String] {
        guard bundleURL.pathExtension == fileExtension else { throw BundleError.wrongExtension(bundleURL) }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: bundleURL, withIntermediateDirectories: true)
            try fm.createDirectory(at: assetsDirectory(in: bundleURL), withIntermediateDirectories: true)
        } catch {
            throw BundleError.writeFailed(bundleURL, error.localizedDescription)
        }

        // Write document.json atomically.
        let docURL = documentFile(in: bundleURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(document)
            try data.write(to: docURL, options: [.atomic])
        } catch {
            throw BundleError.writeFailed(docURL, error.localizedDescription)
        }

        // Copy assets, when a source directory was supplied. Files already
        // present in the bundle's Assets/ with the same name are left alone
        // (write is idempotent on already-bundled docs).
        var copied: [String] = []
        if let source = sourceAssetsDirectory {
            let dest = assetsDirectory(in: bundleURL)
            for asset in document.assets {
                let src = source.appendingPathComponent(asset.path)
                let dst = dest.appendingPathComponent(asset.path)
                guard fm.fileExists(atPath: src.path) else { continue }
                // Skip if destination already matches source (cheap mtime check).
                if fm.fileExists(atPath: dst.path),
                   let dstMod = try? dst.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   let srcMod = try? src.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   dstMod >= srcMod {
                    copied.append(asset.path)
                    continue
                }
                try? fm.removeItem(at: dst)
                do {
                    try fm.copyItem(at: src, to: dst)
                    copied.append(asset.path)
                } catch {
                    throw BundleError.writeFailed(dst, error.localizedDescription)
                }
            }
        } else {
            // Bundle is already self-contained; report what's there.
            let dest = assetsDirectory(in: bundleURL)
            for asset in document.assets where fm.fileExists(atPath: dest.appendingPathComponent(asset.path).path) {
                copied.append(asset.path)
            }
        }
        return copied
    }
}
