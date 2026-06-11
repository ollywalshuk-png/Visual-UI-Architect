import SwiftUI
import AppKit
import UniformTypeIdentifiers
import VUACore

/// Asset library: import PNG/JPEG/SVG/PDF, search by name/tag, and drag assets
/// onto the canvas. Each asset can be assigned, replaced, tagged, locked, or
/// deleted.
struct AssetBrowserView: View {
    @EnvironmentObject var store: DocumentStore
    @State private var search = ""

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 8)]

    private var assets: [Asset] {
        let all = store.document.assets
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.tags.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { importAssets() } label: { Label("Import", systemImage: "square.and.arrow.down") }
                Spacer()
            }
            .padding(8)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search name or tag", text: $search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 8).padding(.bottom, 8)
            Divider()

            if store.document.assets.isEmpty {
                ContentUnavailableViewCompat(
                    title: "No Assets",
                    systemImage: "photo.on.rectangle.angled",
                    description: "Import PNG, JPEG, SVG, or PDF assets to use as backgrounds and artwork.")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(assets) { asset in
                            AssetCell(asset: asset, fileURL: store.assetsDirectory.appendingPathComponent(asset.path))
                        }
                    }
                    .padding(8)
                }
            }

            if !store.repositoryStatus.isEmpty {
                Divider()
                Text(store.repositoryStatus).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
        }
    }

    private func importAssets() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg, .svg, .pdf]
        if panel.runModal() == .OK { store.importAssets(from: panel.urls) }
    }
}

/// A single asset thumbnail with drag-out, assign, replace, tag, lock, delete.
private struct AssetCell: View {
    @EnvironmentObject var store: DocumentStore
    let asset: Asset
    let fileURL: URL
    @State private var showTags = false
    @State private var showMetadata = false
    @State private var tagText = ""

    var body: some View {
        VStack(spacing: 4) {
            thumbnail
                .frame(width: 76, height: 60)
                .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topTrailing) {
                    if asset.isLocked {
                        Image(systemName: "lock.fill").font(.caption2)
                            .padding(3).foregroundStyle(.orange)
                    }
                }
                .overlay(alignment: .bottomLeading) { roleBadge }
            Text(asset.name).font(.caption2).lineLimit(1)
        }
        .padding(4)
        .contentShape(Rectangle())
        // Drag the asset id onto the canvas to create a layer.
        .onDrag { NSItemProvider(object: asset.id.uuidString as NSString) }
        .help(asset.tags.isEmpty ? asset.name : "\(asset.name) — \(asset.tags.joined(separator: ", "))")
        .contextMenu {
            Button("Assign to Selection") { store.assignAssetToSelection(asset.id) }
            Button("Replace…") { replace() }
            Button(asset.isLocked ? "Unlock" : "Lock") { store.toggleAssetLock(asset.id) }
            Button("Edit Tags…") { tagText = asset.tags.joined(separator: ", "); showTags = true }
            Button("Functional Metadata…") { showMetadata = true }
            Divider()
            Button("Delete", role: .destructive) { store.deleteAsset(asset.id) }
        }
        .sheet(isPresented: $showMetadata) {
            AssetMetadataInspectorView(asset: asset).environmentObject(store)
        }
        .popover(isPresented: $showTags) {
            VStack(alignment: .leading) {
                Text("Tags (comma-separated)").font(.caption)
                TextField("panel, knob, bg", text: $tagText)
                    .frame(width: 200)
                    .onSubmit { commitTags() }
                Button("Save") { commitTags() }
            }
            .padding()
        }
    }

    /// Small role badge shown on the thumbnail for assets carrying Phase-17
    /// functional metadata. Empty when the asset is purely decorative.
    @ViewBuilder
    private var roleBadge: some View {
        if let role = asset.metadata?.role, role != .decoration {
            Text(role.displayName)
                .font(.system(size: 8, weight: .semibold))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Color.accentColor.opacity(0.85), in: Capsule())
                .foregroundStyle(.white)
                .padding(3)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        // Single shared resolution pipeline (same as the canvas renderer).
        if let image = AssetResolver.shared.image(for: asset, in: fileURL.deletingLastPathComponent()) {
            Image(nsImage: image).resizable().scaledToFit().padding(2)
        } else {
            Image(systemName: asset.format.isVector ? "scribble.variable" : "photo")
                .imageScale(.large).foregroundStyle(.secondary)
        }
    }

    private func commitTags() {
        let tags = tagText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        store.setAssetTags(asset.id, tags: tags)
        showTags = false
    }

    private func replace() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .svg, .pdf]
        if panel.runModal() == .OK, let url = panel.url {
            store.replaceAsset(asset.id, withFileAt: url)
        }
    }
}
