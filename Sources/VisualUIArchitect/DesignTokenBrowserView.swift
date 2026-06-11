import SwiftUI
import VUACore

struct DesignTokenBrowserView: View {
    @EnvironmentObject var store: DocumentStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.designTokens.isEmpty {
                ContentUnavailableViewCompat(
                    title: "No Tokens",
                    systemImage: "swatchpalette",
                    description: "Create reusable colours, type, spacing, radius, shadows, gradients, and materials.")
                    .padding()
            } else {
                List {
                    ForEach(DesignTokenKind.allCases, id: \.self) { kind in
                        let tokens = store.designTokens.filter { $0.kind == kind }
                        if !tokens.isEmpty {
                            Section(kind.rawValue.capitalized) {
                                ForEach(tokens) { token in row(token) }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Tokens").font(.headline)
            Spacer()
            Text("\(store.designTokens.count)").font(.caption).foregroundStyle(.secondary)
            Button { store.addDefaultDesignTokens() } label: { Image(systemName: "plus.circle") }
                .buttonStyle(.borderless)
                .help("Add default token set")
        }
        .padding(8)
    }

    private func row(_ token: DesignToken) -> some View {
        HStack(spacing: 8) {
            swatch(token)
            VStack(alignment: .leading, spacing: 2) {
                Text(token.name).fontWeight(.medium)
                Text(description(token)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button { store.applyTokenToSelection(token) } label: { Image(systemName: "paintbrush") }
                .disabled(store.selection.isEmpty)
                .buttonStyle(.borderless)
                .help("Apply token to selected layer")
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func swatch(_ token: DesignToken) -> some View {
        switch token.value {
        case .color(let color):
            Circle().fill(color.swiftUI).frame(width: 18, height: 18)
        case .gradient:
            Circle().fill(LinearGradient(colors: [.blue, .green], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 18, height: 18)
        case .material:
            Image(systemName: "square.on.square.dashed").foregroundStyle(.secondary)
        default:
            Image(systemName: "circle.grid.2x2").foregroundStyle(.secondary)
        }
    }

    private func description(_ token: DesignToken) -> String {
        switch token.value {
        case .color: return "Colour"
        case .typography(let size, let weight): return "Type \(Int(size)) \(weight?.rawValue ?? "regular")"
        case .spacing(let value): return "Spacing \(Int(value))"
        case .cornerRadius(let value): return "Radius \(Int(value))"
        case .shadow(let shadow): return "Shadow r\(Int(shadow.radius))"
        case .gradient: return "Gradient"
        case .material(let material): return material
        }
    }
}
