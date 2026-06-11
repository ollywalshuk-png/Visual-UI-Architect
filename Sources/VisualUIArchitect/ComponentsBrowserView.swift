import SwiftUI
import VUACore
import ComponentEngine

/// Components sidebar: list of masters with instance counts, plus actions to
/// create / insert / detach / rename / delete and view diagnostics.
struct ComponentsBrowserView: View {
    @EnvironmentObject var store: DocumentStore
    @State private var newComponentName: String = ""
    @State private var showCreate = false
    @State private var renamingID: UUID?
    @State private var renameDraft: String = ""

    private var counts: [UUID: Int] { store.componentInstanceCounts() }
    private var diagnostics: [ComponentEngine.Diagnostic] { store.componentDiagnostics() }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.components.isEmpty {
                ContentUnavailableViewCompat(
                    title: "No Components",
                    systemImage: "square.on.square.dashed",
                    description: "Select layers on the canvas and press “Create from Selection” to make a reusable component.")
            } else {
                list
            }
            if !diagnostics.isEmpty {
                Divider()
                diagnosticsFooter
            }
        }
        .sheet(isPresented: $showCreate) { createSheet }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                newComponentName = ""
                showCreate = true
            } label: {
                Label("Create from Selection", systemImage: "square.on.square.intersection.dashed")
            }
            .buttonStyle(.borderless)
            .disabled(store.selection.isEmpty)
            Spacer()
            Text("\(store.components.count)")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15), in: Capsule())
        }
        .padding(8)
    }

    private var list: some View {
        List {
            ForEach(store.components) { component in
                row(component)
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ component: Component) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "square.on.square").foregroundStyle(.secondary)
                Text(component.name).fontWeight(.medium)
                Spacer()
                Text("\(counts[component.id] ?? 0)")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                Menu {
                    Button("Insert Instance") { store.insertComponentInstance(component.id) }
                    Button("Update All Instances") { store.updateInstancesOfComponent(component.id) }
                    Button("Create Standard Variants") { store.createStandardVariants(for: component.id) }
                    Divider()
                    Button("Rename…") { renameDraft = component.name; renamingID = component.id }
                    Button("Delete (detach instances)", role: .destructive) {
                        store.deleteComponent(component.id, detachInstances: true)
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { store.insertComponentInstance(component.id) }
            if let category = component.category, !category.isEmpty {
                Text(category).font(.caption2).foregroundStyle(.secondary)
            }
            if !component.variants.isEmpty {
                Text(component.variants.map(\.name).joined(separator: " / "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .alert("Rename Component", isPresented: Binding(
            get: { renamingID == component.id },
            set: { if !$0 { renamingID = nil } })) {
            TextField("Name", text: $renameDraft)
            Button("Save") {
                store.renameComponent(component.id, to: renameDraft); renamingID = nil
            }
            Button("Cancel", role: .cancel) { renamingID = nil }
        }
    }

    private var createSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Component").font(.headline)
            Text("Wraps the current selection (\(store.selection.count) layer\(store.selection.count == 1 ? "" : "s")) into a reusable component.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Component name", text: $newComponentName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { showCreate = false }
                Button("Create") {
                    if store.createComponentFromSelection(named: newComponentName) != nil {
                        showCreate = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newComponentName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private var diagnosticsFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Diagnostics").font(.caption).foregroundStyle(.secondary)
            ForEach(diagnostics.prefix(4)) { d in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: icon(d.severity)).foregroundStyle(color(d.severity)).font(.caption)
                    Text(d.message).font(.caption2)
                    Spacer()
                }
            }
            if diagnostics.count > 4 {
                Text("+ \(diagnostics.count - 4) more").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(8)
    }

    private func icon(_ s: ComponentEngine.Diagnostic.Severity) -> String {
        ["info.circle", "exclamationmark.triangle.fill", "xmark.octagon.fill"][s.rawValue]
    }
    private func color(_ s: ComponentEngine.Diagnostic.Severity) -> Color {
        [Color.secondary, .orange, .red][s.rawValue]
    }
}
