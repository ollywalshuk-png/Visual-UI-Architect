import SwiftUI
import VUACore
import AssetEngine

/// Form for editing an asset's functional metadata (Phase 17): role,
/// function, interaction, rotation/drag behaviour, and the production
/// control binding (parameter id, range, unit, MIDI CC, AU id, automation).
struct AssetMetadataInspectorView: View {
    @EnvironmentObject var store: DocumentStore
    @Environment(\.dismiss) private var dismiss
    let asset: Asset

    /// Resolves the asset's current metadata each render so this view always
    /// reflects the store. Edits flow through the store extension API.
    private var metadata: AssetMetadata {
        store.document.asset(id: asset.id)?.metadata ?? AssetMetadata()
    }

    private var diagnostics: [AssetMetadataDiagnostics.Issue] {
        guard let current = store.document.asset(id: asset.id) else { return [] }
        return AssetMetadataDiagnostics.validate(current)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Asset Metadata", systemImage: "tag.fill").font(.headline)
                Spacer()
                Text(asset.name).foregroundStyle(.secondary)
            }
            .padding()
            Divider()

            Form {
                Section("Role & function") { roleSection }
                Section("Parameter binding") { bindingSection }
                if metadata.function == .rotaryControl { Section("Rotation") { rotationSection } }
                if metadata.function == .linearControl { Section("Drag") { dragSection } }
                Section("Automation") { automationSection }
                if !diagnostics.isEmpty {
                    Section("Diagnostics") { diagnosticsList }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Clear Metadata", role: .destructive) {
                    store.clearAssetMetadata(asset.id)
                }
                .disabled(store.document.asset(id: asset.id)?.metadata == nil)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 460, minHeight: 520)
    }

    // MARK: - Sections

    private var roleSection: some View {
        Group {
            LabeledContent("Role") {
                Picker("", selection: Binding(
                    get: { metadata.role },
                    set: { store.setAssetRole(asset.id, role: $0) })) {
                    ForEach(AssetRole.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
            }
            LabeledContent("Function") {
                Picker("", selection: Binding(
                    get: { metadata.function },
                    set: { v in store.updateAssetMetadata(asset.id) { $0.function = v } })) {
                    ForEach(AssetFunction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
            }
            LabeledContent("Interaction") {
                Picker("", selection: Binding(
                    get: { metadata.interaction },
                    set: { v in store.updateAssetMetadata(asset.id) { $0.interaction = v } })) {
                    ForEach(InteractionType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
            }
        }
    }

    private var bindingSection: some View {
        Group {
            LabeledContent("Parameter ID") {
                TextField("e.g. cutoff", text: Binding(
                    get: { metadata.binding.parameterID ?? "" },
                    set: { v in store.updateAssetMetadata(asset.id) { $0.binding.parameterID = v.isEmpty ? nil : v } }))
                .textFieldStyle(.roundedBorder).frame(width: 200)
            }
            LabeledContent("Display Name") {
                TextField("e.g. Filter Cutoff", text: Binding(
                    get: { metadata.binding.displayName ?? "" },
                    set: { v in store.updateAssetMetadata(asset.id) { $0.binding.displayName = v.isEmpty ? nil : v } }))
                .textFieldStyle(.roundedBorder).frame(width: 200)
            }
            optionalNumberRow("Min", get: { metadata.binding.minValue }, set: { v in
                store.updateAssetMetadata(asset.id) { $0.binding.minValue = v } })
            optionalNumberRow("Max", get: { metadata.binding.maxValue }, set: { v in
                store.updateAssetMetadata(asset.id) { $0.binding.maxValue = v } })
            optionalNumberRow("Default", get: { metadata.binding.defaultValue }, set: { v in
                store.updateAssetMetadata(asset.id) { $0.binding.defaultValue = v } })
            LabeledContent("Unit") {
                Picker("", selection: Binding(
                    get: { metadata.binding.unit },
                    set: { v in store.updateAssetMetadata(asset.id) { $0.binding.unit = v } })) {
                    ForEach(ControlUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
            }
            Toggle("Continuous", isOn: Binding(
                get: { metadata.binding.isContinuous },
                set: { v in store.updateAssetMetadata(asset.id) { $0.binding.isContinuous = v } }))
            if !metadata.binding.isContinuous {
                LabeledContent("Steps") {
                    TextField("steps", value: Binding(
                        get: { metadata.binding.stepCount ?? 2 },
                        set: { v in store.updateAssetMetadata(asset.id) { $0.binding.stepCount = v } }), format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 70)
                }
            }
        }
    }

    private var rotationSection: some View {
        let rot = metadata.rotation ?? RotationBehaviour()
        return Group {
            inlineNumber("Min°", rot.minDegrees) { v in
                store.updateAssetMetadata(asset.id) { $0.rotation = updated($0.rotation) { $0.minDegrees = v } } }
            inlineNumber("Max°", rot.maxDegrees) { v in
                store.updateAssetMetadata(asset.id) { $0.rotation = updated($0.rotation) { $0.maxDegrees = v } } }
            inlineNumber("Zero°", rot.zeroDegrees) { v in
                store.updateAssetMetadata(asset.id) { $0.rotation = updated($0.rotation) { $0.zeroDegrees = v } } }
        }
    }

    private var dragSection: some View {
        let d = metadata.drag ?? DragBehaviour()
        return Group {
            LabeledContent("Axis") {
                Picker("", selection: Binding(
                    get: { d.axis },
                    set: { v in store.updateAssetMetadata(asset.id) { $0.drag = updated($0.drag) { $0.axis = v } } })) {
                    ForEach(DragBehaviour.Axis.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
            }
            inlineNumber("Pixels/Sweep", d.pixelsPerFullSweep) { v in
                store.updateAssetMetadata(asset.id) { $0.drag = updated($0.drag) { $0.pixelsPerFullSweep = v } } }
        }
    }

    /// Inline numeric LabeledContent — avoids the actor-isolation cascade that
    /// `numberRow(_:value:set:)` ran into with `@Sendable` bindings.
    @ViewBuilder
    private func inlineNumber(_ title: String, _ value: Double, _ set: @escaping (Double) -> Void) -> some View {
        LabeledContent(title) {
            TextField(title,
                      value: Binding(get: { value }, set: { v in set(v) }),
                      format: .number.precision(.fractionLength(0...2)))
            .textFieldStyle(.roundedBorder).frame(width: 100)
        }
    }

    private var automationSection: some View {
        Group {
            Toggle("Automation enabled", isOn: Binding(
                get: { metadata.binding.automationEnabled },
                set: { v in store.updateAssetMetadata(asset.id) { $0.binding.automationEnabled = v } }))
            LabeledContent("MIDI CC") {
                TextField("0…127", value: Binding(
                    get: { metadata.binding.midiCC ?? 0 },
                    set: { v in store.updateAssetMetadata(asset.id) { $0.binding.midiCC = (v >= 0 && v <= 127) ? v : nil } }),
                    format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 80)
            }
            LabeledContent("AU Parameter ID") {
                TextField("e.g. au_cutoff", text: Binding(
                    get: { metadata.binding.auParameterID ?? "" },
                    set: { v in store.updateAssetMetadata(asset.id) { $0.binding.auParameterID = v.isEmpty ? nil : v } }))
                .textFieldStyle(.roundedBorder).frame(width: 200)
            }
        }
    }

    private var diagnosticsList: some View {
        ForEach(diagnostics) { issue in
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: icon(issue.severity)).foregroundStyle(color(issue.severity))
                Text(issue.message).font(.callout)
                Spacer()
                Text(issue.code.rawValue).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Helpers

    private func optionalNumberRow(_ title: String,
                                   get: @escaping () -> Double?,
                                   set: @escaping (Double?) -> Void) -> some View {
        LabeledContent(title) {
            TextField("—", text: Binding(
                get: { get().map { String($0) } ?? "" },
                set: { txt in
                    let v = Double(txt.trimmingCharacters(in: .whitespaces))
                    set(v)
                }))
            .textFieldStyle(.roundedBorder).frame(width: 100)
        }
    }


    /// Returns a mutated copy of `value`, constructing one via `fallback` when
    /// `value` is nil so the first edit on an empty optional always sticks.
    private func updated<T>(_ value: T?, fallback: @autoclosure () -> T,
                            _ transform: (inout T) -> Void) -> T {
        var v = value ?? fallback()
        transform(&v)
        return v
    }

    private func updated(_ value: RotationBehaviour?, _ transform: (inout RotationBehaviour) -> Void) -> RotationBehaviour {
        updated(value, fallback: RotationBehaviour(), transform)
    }

    private func updated(_ value: DragBehaviour?, _ transform: (inout DragBehaviour) -> Void) -> DragBehaviour {
        updated(value, fallback: DragBehaviour(), transform)
    }

    private func icon(_ s: AssetMetadataDiagnostics.Issue.Severity) -> String {
        ["info.circle", "exclamationmark.triangle.fill", "xmark.octagon.fill"][s.rawValue]
    }
    private func color(_ s: AssetMetadataDiagnostics.Issue.Severity) -> Color {
        [Color.secondary, .orange, .red][s.rawValue]
    }
}
