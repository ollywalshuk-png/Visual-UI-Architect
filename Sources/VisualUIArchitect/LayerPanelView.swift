import SwiftUI
import VUACore

/// Photoshop-style layer hierarchy with visibility/lock toggles, search, and
/// selection synced to the canvas.
struct LayerPanelView: View {
    @EnvironmentObject var store: DocumentStore
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter layers", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            Divider()

            List {
                // Render in display order (front-most on top), reversing z-order.
                ForEach(store.document.roots.reversed()) { layer in
                    LayerRow(layer: layer, depth: 0, search: search)
                }
            }
            .listStyle(.sidebar)
        }
    }
}

private struct LayerRow: View {
    @EnvironmentObject var store: DocumentStore
    let layer: Layer
    let depth: Int
    let search: String

    private var matches: Bool {
        search.isEmpty || layer.name.localizedCaseInsensitiveContains(search)
    }

    var body: some View {
        if matches || hasMatchingDescendant {
            row
            ForEach(layer.children.reversed()) { child in
                LayerRow(layer: child, depth: depth + 1, search: search)
            }
        }
    }

    private var hasMatchingDescendant: Bool {
        guard !search.isEmpty else { return false }
        return layer.flattened().contains { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var row: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(depth) * 12, height: 1)
            Image(systemName: icon(for: layer.kind))
                .frame(width: 16)
                .foregroundStyle(layer.labelColor?.swiftUI ?? .secondary)
            Text(layer.name).lineLimit(1)
            Spacer()
            Button { store.reorderLayerTowardFront(layer.id) } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(!store.canReorderLayer(layer.id, towardFront: true))
            .help("Move up (draw on top)")
            Button { store.reorderLayerTowardBack(layer.id) } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(!store.canReorderLayer(layer.id, towardFront: false))
            .help("Move down (draw underneath)")
            Button { store.setVisibility(layer.id, !layer.isVisible) } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(layer.isVisible ? .secondary : .tertiary)
            }
            .buttonStyle(.borderless)
            Button { store.setLocked(layer.id, !layer.isLocked) } label: {
                Image(systemName: layer.isLocked ? "lock.fill" : "lock.open")
                    .foregroundStyle(layer.isLocked ? .orange : .secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .listRowBackground(store.selection.contains(layer.id) ? Color.accentColor.opacity(0.25) : Color.clear)
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.command) {
                if store.selection.contains(layer.id) { store.selection.remove(layer.id) }
                else { store.selection.insert(layer.id) }
            } else {
                store.selection = [layer.id]
            }
        }
        .contextMenu {
            Button("Move Up") { store.reorderLayerTowardFront(layer.id) }
                .disabled(!store.canReorderLayer(layer.id, towardFront: true))
            Button("Move Down") { store.reorderLayerTowardBack(layer.id) }
                .disabled(!store.canReorderLayer(layer.id, towardFront: false))
            Divider()
            Button("Group") { selectIfNeeded(layer.id); store.groupSelection() }
                .disabled(!store.canGroup && store.selection != [layer.id])
            Button("Ungroup") { store.selection = [layer.id]; store.ungroupSelection() }
                .disabled(!layer.kind.isGroupLike)
            Divider()
            Button("Copy") { selectIfNeeded(layer.id); store.copySelection() }
            Button("Paste") { store.paste() }.disabled(!store.canPaste)
            Button("Duplicate") { store.selection = [layer.id]; store.duplicateSelection() }
            Button("Delete", role: .destructive) { selectIfNeeded(layer.id); store.deleteSelection() }
        }
    }

    private func selectIfNeeded(_ id: UUID) {
        if !store.selection.contains(id) { store.selection = [id] }
    }

    private func icon(for kind: LayerKind) -> String {
        switch kind {
        case .button: return "rectangle.roundedtop"
        case .label, .text: return "textformat"
        case .image: return "photo"
        case .slider: return "slider.horizontal.3"
        case .knob: return "dial.min"
        case .fader: return "slider.vertical.3"
        case .meter: return "chart.bar"
        case .toggle: return "switch.2"
        case .panel, .container: return "square.on.square"
        case .background: return "rectangle.inset.filled"
        case .group: return "folder"
        case .shape(let s): return shapeIcon(s)
        case .line: return "line.diagonal"
        case .vectorPath: return "point.topleft.down.curvedto.point.bottomright.up"
        case .polygon: return "pentagon"
        case .gradient: return "circle.lefthalf.filled"
        case .mask: return "theatermasks"
        case .control, .custom: return "cube"
        }
    }

    private func shapeIcon(_ s: ShapeKind) -> String {
        switch s {
        case .rectangle, .card, .glassPanel: return "rectangle"
        case .roundedRectangle, .callout: return "rectangle.roundedtop"
        case .ellipse: return "circle"
        case .capsule: return "capsule"
        case .star: return "star"
        case .divider: return "minus"
        }
    }
}
