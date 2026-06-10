import SwiftUI
import VUACore
import PresetEngine

/// Browser for the advanced control-preset catalog (250 entries).
///
/// Layout: a kind selector at the top (Knobs / Faders / Sliders / Buttons /
/// Switches), a family filter, and a live-preview grid. Search runs across
/// name, family, and tags. Tap → insert at canvas centre.
struct ControlPresetsBrowserView: View {
    @EnvironmentObject var store: DocumentStore
    @State private var search = ""
    @State private var kind: ControlPresetKind = .knob
    @State private var family: String? = nil   // nil = all families

    private var families: [String] { ControlPresetLibrary.families(in: kind) }

    private var filtered: [ControlPreset] {
        var pool = ControlPresetLibrary.search(search, in: kind)
        if let family { pool = pool.filter { $0.family == family } }
        return pool
    }

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            kindPicker
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search by name, family, or tag", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            familyChips
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filtered) { preset in
                        cell(preset)
                    }
                }
                .padding(10)
            }
            Divider()
            Text("\(filtered.count) preset\(filtered.count == 1 ? "" : "s") · \(ControlPresetLibrary.all.count) total")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
        .onChange(of: kind) { _, _ in family = nil }
    }

    // MARK: - Sections

    private var kindPicker: some View {
        Picker("", selection: $kind) {
            ForEach(ControlPresetKind.allCases, id: \.self) { k in
                Text(k.displayName).tag(k)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(8)
    }

    private var familyChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("All", selected: family == nil) { family = nil }
                ForEach(families, id: \.self) { f in
                    chip(f, selected: family == f) { family = (family == f) ? nil : f }
                }
            }
            .padding(.horizontal, 8).padding(.bottom, 6)
        }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(selected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12),
                            in: Capsule())
                .overlay(Capsule().stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cell

    @ViewBuilder
    private func cell(_ preset: ControlPreset) -> some View {
        VStack(spacing: 4) {
            ControlPresetThumbnail(preset: preset)
                .frame(width: 88, height: 64)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
            Text(preset.name)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 92, height: 26)
        }
        .padding(4)
        .contentShape(Rectangle())
        .onTapGesture { store.insertControlPreset(preset) }
        .help(preset.tags.joined(separator: ", "))
    }
}

/// Live SwiftUI preview of a control preset — renders the same layer that
/// would land on the canvas, scaled into the cell. Avoids generating PNGs.
struct ControlPresetThumbnail: View {
    let preset: ControlPreset

    var body: some View {
        GeometryReader { geo in
            // Fit the preset's natural size into the cell, preserving aspect.
            let scale = min(geo.size.width / max(1, preset.size.width),
                            geo.size.height / max(1, preset.size.height)) * 0.8
            let layer = preset.makeLayer(at: .zero)
            LayerRenderView(layer: layer, asset: nil, resolution: nil)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
