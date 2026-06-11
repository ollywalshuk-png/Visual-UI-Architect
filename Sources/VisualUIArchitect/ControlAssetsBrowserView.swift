import SwiftUI
import VUACore
import PresetEngine

/// Browser for Phase 19 functional control assets. These complement the
/// Phase 16 preset browser by surfacing role/function/behaviour metadata.
struct ControlAssetsBrowserView: View {
    @EnvironmentObject var store: DocumentStore
    @State private var search = ""
    @State private var category: ControlAssetCategory = .knob

    private var filtered: [ControlAsset] {
        ControlAssetLibrary.search(search, in: category)
    }

    private let columns = [GridItem(.adaptive(minimum: 102), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $category) {
                ForEach(ControlAssetCategory.allCases, id: \.self) { category in
                    Text(category.displayName).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search assets", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filtered) { asset in
                        cell(asset)
                    }
                }
                .padding(10)
            }

            Divider()
            Text("\(filtered.count) asset\(filtered.count == 1 ? "" : "s") · \(ControlAssetLibrary.all.count) total")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
    }

    private func cell(_ asset: ControlAsset) -> some View {
        VStack(spacing: 5) {
            ControlAssetThumbnail(asset: asset)
                .frame(width: 92, height: 66)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
            Text(asset.name)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 96, height: 26)
            Text(asset.behaviour.displayName)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 96)
        }
        .padding(4)
        .contentShape(Rectangle())
        .onTapGesture { store.insertControlAsset(asset) }
        .help(helpText(for: asset))
    }

    private func helpText(for asset: ControlAsset) -> String {
        let range = asset.valueRange.map { "\($0.lowerBound)...\($0.upperBound)" } ?? "none"
        return [
            asset.role.displayName,
            asset.function.rawValue,
            asset.behaviour.displayName,
            "range \(range)",
            asset.tags.joined(separator: ", ")
        ].joined(separator: " · ")
    }
}

struct ControlAssetThumbnail: View {
    let asset: ControlAsset

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / max(1, asset.defaultSize.width),
                            geo.size.height / max(1, asset.defaultSize.height)) * 0.8
            let layer = asset.makeLayer(at: .zero)
            LayerRenderView(layer: layer, asset: nil, resolution: nil)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
