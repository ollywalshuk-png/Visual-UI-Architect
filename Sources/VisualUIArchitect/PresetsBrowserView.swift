import SwiftUI
import PresetEngine

/// Presets browser: grouped, searchable catalog of insertable layout presets.
struct PresetsBrowserView: View {
    @EnvironmentObject var store: DocumentStore
    @State private var search = ""

    private var filtered: [Preset] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return PresetLibrary.all }
        return PresetLibrary.all.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.category.rawValue.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search presets", text: $search).textFieldStyle(.plain)
            }
            .padding(8)
            Divider()

            List {
                ForEach(Preset.Category.allCases, id: \.self) { category in
                    let items = filtered.filter { $0.category == category }
                    if !items.isEmpty {
                        Section(category.rawValue) {
                            ForEach(items) { preset in
                                Button {
                                    store.insertPreset(preset)
                                } label: {
                                    HStack {
                                        Image(systemName: "rectangle.3.group").foregroundStyle(.secondary)
                                        Text(preset.name).lineLimit(1)
                                        Spacer()
                                        Image(systemName: "plus.circle").foregroundStyle(.tertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            Text("\(PresetLibrary.all.count) presets")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }
}
