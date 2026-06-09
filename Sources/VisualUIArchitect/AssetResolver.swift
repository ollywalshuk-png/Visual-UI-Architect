import Foundation
import AppKit
import VUACore
import AssetEngine

/// The single image-resolution pipeline used by the asset browser, canvas
/// renderer, and previews:
///
///   Asset → AssetLibrary.fileURL(in:) → NSImage(contentsOf:) → cached image
///
/// Caching is keyed by path + modification date so replacing an asset on disk
/// invalidates the cached image.
final class AssetResolver: @unchecked Sendable {
    static let shared = AssetResolver()

    private let cache = NSCache<NSString, NSImage>()

    enum Resolution {
        case image(NSImage)
        case missingFile          // asset record exists, file not found
        case decodeFailed         // file exists but couldn't be decoded
    }

    /// Resolved file URL for an asset within a directory.
    func url(for asset: Asset, in directory: URL) -> URL {
        AssetLibrary.fileURL(for: asset, in: directory)
    }

    /// Loads (and caches) the image for an asset, reporting why it failed.
    func resolve(_ asset: Asset, in directory: URL) -> Resolution {
        let fileURL = url(for: asset, in: directory)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .missingFile
        }
        let mtime = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
            .timeIntervalSince1970 ?? 0
        let key = "\(fileURL.path)#\(mtime)" as NSString
        if let cached = cache.object(forKey: key) {
            return .image(cached)
        }
        // NSImage(contentsOf:) handles PNG/JPEG/PDF and (macOS 13+) SVG.
        guard let image = NSImage(contentsOf: fileURL) else {
            return .decodeFailed
        }
        cache.setObject(image, forKey: key)
        return .image(image)
    }

    /// Convenience returning the image or nil.
    func image(for asset: Asset, in directory: URL) -> NSImage? {
        if case .image(let img) = resolve(asset, in: directory) { return img }
        return nil
    }
}
