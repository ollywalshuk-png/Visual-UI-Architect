import Foundation
import VUACore
import LayerEngine
import AssetEngine
import PersistenceEngine

/// Asset-library features on the document store: import, assign, replace, tag,
/// lock, and dropping assets onto the canvas as image layers.
extension DocumentStore {

    /// Directory where imported assets are stored. Resolution order:
    /// 1. The open `.vuaproj` bundle's `Assets/` (self-contained projects).
    /// 2. The open repository's `Assets/` (Phase 2 round-trip).
    /// 3. Application Support fallback (untitled documents).
    var assetsDirectory: URL {
        if let url = documentURL {
            return VUABundle.assetsDirectory(in: url)
        }
        if let root = repositoryRoot {
            return root.appendingPathComponent("Assets")
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("VisualUIArchitect/Assets")
    }

    private var library: AssetLibrary { AssetLibrary(assetsDirectory: assetsDirectory) }

    // MARK: - Import / manage

    func importAssets(from urls: [URL]) {
        let imported = library.importAssets(from: urls)
        guard !imported.isEmpty else {
            repositoryStatus = "No supported assets imported."
            return
        }
        mutate { $0.assets.append(contentsOf: imported) }
        repositoryStatus = "Imported \(imported.count) asset(s)."
    }

    func replaceAsset(_ assetID: UUID, withFileAt url: URL) {
        guard let asset = document.asset(id: assetID),
              let updated = library.replace(asset, withFileAt: url) else {
            repositoryStatus = "Could not replace asset."
            return
        }
        mutate { doc in
            if let i = doc.assets.firstIndex(where: { $0.id == assetID }) { doc.assets[i] = updated }
        }
        repositoryStatus = "Replaced \(updated.name)."
    }

    func setAssetTags(_ assetID: UUID, tags: [String]) {
        mutate { doc in
            if let i = doc.assets.firstIndex(where: { $0.id == assetID }) { doc.assets[i].tags = tags }
        }
    }

    func toggleAssetLock(_ assetID: UUID) {
        mutate { doc in
            if let i = doc.assets.firstIndex(where: { $0.id == assetID }) { doc.assets[i].isLocked.toggle() }
        }
    }

    func deleteAsset(_ assetID: UUID) {
        mutate { doc in
            doc.assets.removeAll { $0.id == assetID }
            // Detach any layers that referenced it.
            for layer in doc.allLayers where layer.assetID == assetID {
                LayerTree.update(layer.id, in: &doc.roots) { $0.assetID = nil }
            }
        }
    }

    // MARK: - Use on canvas

    /// Assigns an asset to the current single selection (image/background).
    func assignAssetToSelection(_ assetID: UUID) {
        guard let id = selection.first else { return }
        mutate { LayerTree.update(id, in: &$0.roots) { $0.assetID = assetID } }
    }

    /// Creates an image layer for an asset at a canvas point (drag-drop target).
    func dropAsset(_ assetID: UUID, at point: VPoint) {
        guard let asset = document.asset(id: assetID) else { return }
        let placement = AssetLibrary.placement(for: asset)
        let layer = Layer(
            name: asset.name,
            kind: placement.isBackground ? .background : .image,
            frame: placement.frame(centeredOn: point),
            assetID: assetID,
            isLocked: placement.isLocked)
        // Backgrounds go to the back (index 0); everything else on top.
        mutate { LayerTree.insert(layer, into: &$0.roots, parentID: nil, at: placement.isBackground ? 0 : nil) }
        selection = [layer.id]
    }

    // MARK: - Control metadata

    /// Updates the AU parameter metadata of the selected control.
    func updateSelectedControl(_ transform: @escaping (inout ControlMetadata) -> Void) {
        guard let id = selection.first else { return }
        mutate { doc in
            LayerTree.update(id, in: &doc.roots) { layer in
                var meta = layer.control ?? ControlMetadata(parameterID: layer.name.lowercased())
                transform(&meta)
                layer.control = meta
            }
        }
    }
}
