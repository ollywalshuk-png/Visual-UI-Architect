import Foundation
import VUACore
#if canImport(AppKit)
import AppKit
#endif

/// Imports visual assets into a project, copying files into a managed assets
/// directory (sandbox-friendly) and recording intrinsic sizes.
public struct AssetImporter: Sendable {
    /// Directory (inside the project) where imported assets are stored.
    public let assetsDirectory: URL

    public init(assetsDirectory: URL) {
        self.assetsDirectory = assetsDirectory
    }

    public enum ImportError: Error, CustomStringConvertible {
        case unsupportedFormat(String)
        case copyFailed(String)

        public var description: String {
            switch self {
            case .unsupportedFormat(let ext): return "Unsupported asset format: .\(ext)"
            case .copyFailed(let reason): return "Failed to import asset: \(reason)"
            }
        }
    }

    /// Copies the file at `sourceURL` into the assets directory and returns an Asset.
    public func importAsset(from sourceURL: URL) throws -> Asset {
        let ext = sourceURL.pathExtension
        guard let format = Asset.Format(fileExtension: ext) else {
            throw ImportError.unsupportedFormat(ext)
        }

        let fm = FileManager.default
        try fm.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        let destURL = uniqueDestination(for: sourceURL.lastPathComponent)
        do {
            try fm.copyItem(at: sourceURL, to: destURL)
        } catch {
            throw ImportError.copyFailed(error.localizedDescription)
        }

        return Asset(
            name: sourceURL.deletingPathExtension().lastPathComponent,
            path: destURL.lastPathComponent,
            format: format,
            intrinsicSize: intrinsicSize(of: destURL, format: format),
            scale: detectScale(from: sourceURL.lastPathComponent))
    }

    private func uniqueDestination(for fileName: String) -> URL {
        var candidate = assetsDirectory.appendingPathComponent(fileName)
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = assetsDirectory.appendingPathComponent("\(base)-\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    private func detectScale(from fileName: String) -> Int {
        if fileName.contains("@3x") { return 3 }
        if fileName.contains("@2x") { return 2 }
        return 1
    }

    private func intrinsicSize(of url: URL, format: Asset.Format) -> VSize {
        #if canImport(AppKit)
        if let image = NSImage(contentsOf: url) {
            return VSize(width: image.size.width, height: image.size.height)
        }
        #endif
        return .zero
    }
}
