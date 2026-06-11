import Foundation
import VUACore
#if canImport(AppKit)
import AppKit
#endif

/// Manages a collection of assets and their backing files: import, replace,
/// tag, lock, and query. Pure data operations return new arrays so the caller
/// (the document store) keeps undo/redo and persistence.
public struct AssetLibrary: Sendable {
    public let assetsDirectory: URL
    private let importer: AssetImporter

    public init(assetsDirectory: URL) {
        self.assetsDirectory = assetsDirectory
        self.importer = AssetImporter(assetsDirectory: assetsDirectory)
    }

    /// Imports multiple files, skipping unsupported ones. Returns imported assets.
    public func importAssets(from urls: [URL]) -> [Asset] {
        urls.compactMap { try? importer.importAsset(from: $0) }
    }

    /// Replaces an asset's backing file with a new file, preserving the asset id
    /// (so every layer referencing it updates automatically). Returns the
    /// updated asset, or nil if the new file is unsupported.
    public func replace(_ asset: Asset, withFileAt sourceURL: URL) -> Asset? {
        guard let format = Asset.Format(fileExtension: sourceURL.pathExtension) else { return nil }
        let fm = FileManager.default
        try? fm.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        let dest = assetsDirectory.appendingPathComponent(asset.path)
        try? fm.removeItem(at: dest)
        guard (try? fm.copyItem(at: sourceURL, to: dest)) != nil else { return nil }
        var updated = asset
        updated.format = format
        updated.intrinsicSize = intrinsicSize(of: dest)
        return updated
    }

    /// Filters assets by a search term matched against name and tags.
    public static func filter(_ assets: [Asset], query: String) -> [Asset] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return assets }
        return assets.filter { asset in
            asset.name.localizedCaseInsensitiveContains(q) ||
            asset.tags.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    /// All distinct tags across the given assets, sorted.
    public static func allTags(_ assets: [Asset]) -> [String] {
        Array(Set(assets.flatMap { $0.tags })).sorted()
    }

    // MARK: - Resolution & placement (pure, testable)

    /// Resolves an asset's backing file URL inside an assets directory.
    public static func fileURL(for asset: Asset, in directory: URL) -> URL {
        directory.appendingPathComponent(asset.path)
    }

    /// How a dropped asset should be placed on the canvas. Pure so the geometry
    /// is unit-testable independent of SwiftUI/AppKit.
    public struct Placement: Sendable, Equatable {
        public var size: VSize
        public var isBackground: Bool
        public var isLocked: Bool
        /// Phase 17: the layer kind chosen for the dropped layer (image by
        /// default; knobCap → .knob, faderCap → .fader, etc.).
        public var layerKind: LayerKind
        /// Phase 17: control metadata to attach to the dropped layer when the
        /// asset carries a functional binding.
        public var control: ControlMetadata?
        /// Top-left origin for a drop centered on `point`.
        public func frame(centeredOn point: VPoint) -> VRect {
            VRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                  width: size.width, height: size.height)
        }
    }

    /// Computes placement for an asset: preserves aspect (capped), respects
    /// functional `AssetMetadata` (Phase 17), and treats `bg`/`background`-
    /// tagged assets as locked background layers.
    public static func placement(for asset: Asset, maxDimension: Double = 320) -> Placement {
        let intrinsic = asset.intrinsicSize
        let size: VSize
        if intrinsic.width > 0 && intrinsic.height > 0 {
            let scale = Swift.min(1, maxDimension / Swift.max(intrinsic.width, intrinsic.height))
            size = VSize(width: intrinsic.width * scale, height: intrinsic.height * scale)
        } else {
            size = VSize(width: 120, height: 120)
        }
        let bgTagged = asset.tags.contains {
            $0.localizedCaseInsensitiveContains("bg") || $0.localizedCaseInsensitiveContains("background")
        }
        // Metadata role drives the resulting layer kind / control binding.
        let role = asset.metadata?.role
        let isBackground = bgTagged || role == .backplate
        let kind = layerKind(forRole: role, backgroundFallback: isBackground)
        let control = asset.metadata?.binding.toControlMetadata()
        return Placement(
            size: size,
            isBackground: isBackground,
            isLocked: isBackground,
            layerKind: kind,
            control: control
        )
    }

    /// Maps an asset role to the layer kind it should drop as. Image is the
    /// default for purely decorative artwork.
    public static func layerKind(forRole role: AssetRole?, backgroundFallback: Bool) -> LayerKind {
        switch role {
        case .backplate: return .background
        case .knobCap: return .knob
        case .faderCap: return .fader
        case .meterLED: return .meter
        case .button: return .button
        case .toggleSwitch: return .toggle
        case .faderTrack, .decoration, .icon, .texture, .none:
            return backgroundFallback ? .background : .image
        }
    }

    private func intrinsicSize(of url: URL) -> VSize {
        #if canImport(AppKit)
        if let image = NSImage(contentsOf: url) {
            return VSize(width: image.size.width, height: image.size.height)
        }
        #endif
        return .zero
    }
}
