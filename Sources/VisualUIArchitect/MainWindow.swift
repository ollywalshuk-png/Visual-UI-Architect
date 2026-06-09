import SwiftUI
import VUACore
import RepositoryEngine
import PersistenceEngine

/// Top-level window layout: layer sidebar, canvas, inspector, validation, and
/// the editor toolbar.
struct MainWindow: View {
    @EnvironmentObject var store: DocumentStore
    @EnvironmentObject var theme: ThemeSettings
    @State private var showCode = false
    @State private var showExport = false
    @State private var showSnapshots = false
    @State private var showWorkspace = false
    @State private var showBuild = false
    @State private var showHandoff = false
    @State private var showQuality = false
    @State private var showRecovery = false
    @State private var recovered: PersistenceEngine.RecoveryStore.Recovered?
    @State private var sidebarTab = SidebarTab.layers
    @State private var applyResult: SafeApplyResult?
    @State private var showApplyResult = false

    enum SidebarTab: String, CaseIterable { case layers = "Layers", assets = "Assets", presets = "Presets", repo = "Repository" }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                Picker("", selection: $sidebarTab) {
                    ForEach(SidebarTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(8)
                Divider()
                switch sidebarTab {
                case .layers: LayerPanelView()
                case .assets: AssetBrowserView()
                case .presets: PresetsBrowserView()
                case .repo: RepositoryBrowserView()
                }
            }
            .frame(minWidth: 240)
        } detail: {
            VSplitView {
                HSplitView {
                    CanvasView()
                        .frame(minWidth: 480, minHeight: 360)
                    InspectorView()
                        .frame(minWidth: 280, maxWidth: 360)
                }
                ValidationPanelView()
                    .frame(minHeight: 120, maxHeight: 220)
            }
        }
        .toolbar { toolbarContent }
        .sheet(isPresented: $showCode) { CodePreviewView().environmentObject(store) }
        .sheet(isPresented: $showExport) { ExportPanelView().environmentObject(store) }
        .sheet(isPresented: $showSnapshots) { SnapshotsView().environmentObject(store) }
        .sheet(isPresented: $showWorkspace) { WorkspaceDiagnosticsView().environmentObject(store) }
        .sheet(isPresented: $showBuild) { BuildDiagnosticsView().environmentObject(store) }
        .sheet(isPresented: $showHandoff) { HandoffView().environmentObject(store) }
        .sheet(isPresented: $showQuality) { QualityPanelView().environmentObject(store) }
        .onAppear {
            if let r = store.pendingRecovery() { recovered = r; showRecovery = true }
        }
        .alert("Recover Unsaved Work?", isPresented: $showRecovery, presenting: recovered) { r in
            Button("Restore") { store.restoreRecovery(r) }
            Button("Discard", role: .destructive) { store.discardRecovery() }
            Button("Cancel", role: .cancel) {}
        } message: { r in
            Text("Visual UI Architect found unsaved work from “\(r.meta.documentName)”.\n\(r.conflict.message) Restore it?")
        }
        .alert("Save changes before closing?", isPresented: $store.closeConfirmPending) {
            Button("Save") { if store.save() { store.performClose() } }
            Button("Don't Save", role: .destructive) { store.markClean(); store.performClose() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your changes will be lost if you don't save them.")
        }
        .alert("Save changes first?", isPresented: Binding(
            get: { store.pendingDirtyAction != nil },
            set: { if !$0 { store.pendingDirtyAction = nil } })) {
            Button("Save") { store.resolvePendingDirtyAction(save: true) }
            Button("Don't Save", role: .destructive) { store.resolvePendingDirtyAction(save: false) }
            Button("Cancel", role: .cancel) { store.resolvePendingDirtyAction(save: nil) }
        } message: {
            Text("The current document has unsaved changes. Save before continuing?")
        }
        .sheet(isPresented: $showApplyResult) {
            if let applyResult { ApplyResultView(result: applyResult) }
        }
        .navigationTitle(store.windowTitle)
    }

    private func runApply(build: Bool) {
        if let result = store.applyToSource(runBuild: build) {
            applyResult = result
            showApplyResult = true
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!store.canUndo).help("Undo")
            Button { store.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!store.canRedo).help("Redo")
            Button { store.save() } label: { Image(systemName: "square.and.arrow.down") }
                .disabled(!store.isDirty && store.documentURL != nil)
                .help("Save project")
            Button { showSnapshots = true } label: { Image(systemName: "clock.arrow.circlepath") }
                .disabled(store.documentURL == nil)
                .help("Version snapshots")
        }

        ToolbarItemGroup {
            AddLayerMenu()

            Button { store.duplicateSelection() } label: { Image(systemName: "plus.square.on.square") }
                .disabled(store.selection.isEmpty).help("Duplicate")
            Button { store.deleteSelection() } label: { Image(systemName: "trash") }
                .disabled(store.selection.isEmpty).help("Delete")

            Divider()

            devicePicker
            orientationToggle

            Divider()

            Picker("", selection: Binding(
                get: { theme.theme }, set: { theme.theme = $0 })) {
                ForEach(AppTheme.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu).help("Theme")

            Button { showCode = true } label: {
                Label("Generate Code", systemImage: "curlybraces")
            }
            .help("Generate \(store.document.codeGenTarget.displayName)")

            Button { showExport = true } label: {
                Label("Export", systemImage: "shippingbox")
            }
            .help("Export a portable SwiftUI package (assets + controls + manifests)")

            Button { showWorkspace = true } label: { Label("Workspace", systemImage: "checkmark.shield") }
                .help("Workspace safety diagnostics")
                .disabled(store.repositoryRoot == nil)

            Button { showBuild = true } label: { Label("Build", systemImage: "hammer") }
                .help("Build diagnostics: toolchain, pipeline, repeatable command, failure explanations")
                .disabled(store.repositoryRoot == nil)

            Button { showHandoff = true } label: { Label("Handoff", systemImage: "person.line.dotted.person") }
                .help("Generate an AI/developer continuation handoff (HANDOFF.md)")

            Button { showQuality = true } label: { Label("Quality", systemImage: "gauge.with.needle") }
                .help("UI quality: density, spacing, contrast, accessibility, noise scores")

            Menu {
                Button("Apply (validate + write + diff)") { runApply(build: false) }
                Button("Safe Apply (+ swift build)") { runApply(build: true) }
            } label: {
                Label("Apply to Source", systemImage: "arrow.up.doc")
            }
            .help("Write visual changes back to source")
            .disabled(store.repositoryRoot == nil)
        }
    }

    private var devicePicker: some View {
        Picker("", selection: Binding(
            get: { store.document.activeDevice.id },
            set: { id in
                if let d = DeviceProfile.catalog.first(where: { $0.id == id }) { store.setDevice(d) }
            })) {
            ForEach(DeviceProfile.catalog) { device in
                Label(device.name, systemImage: deviceIcon(device.family)).tag(device.id)
            }
        }
        .pickerStyle(.menu)
        .help("Preview device")
    }

    private var orientationToggle: some View {
        Button {
            store.setOrientation(store.document.activeOrientation == .portrait ? .landscape : .portrait)
        } label: {
            Image(systemName: store.document.activeOrientation == .portrait
                  ? "rectangle.portrait" : "rectangle")
        }
        .disabled(!store.document.activeDevice.supportsLandscape)
        .help("Rotate")
    }

    private func deviceIcon(_ family: DeviceProfile.Family) -> String {
        switch family {
        case .mac: return "desktopcomputer"
        case .iPad: return "ipad"
        case .iPhone: return "iphone"
        case .watch: return "applewatch"
        case .vision: return "visionpro"
        }
    }
}

/// Menu for inserting new layers, grouped into layout, content, and the
/// plugin/synth control palette.
struct AddLayerMenu: View {
    @EnvironmentObject var store: DocumentStore

    private let layout: [LayerKind] = [.panel, .container, .background, .group]
    private let content: [LayerKind] = [.button, .label, .text, .image]
    private let controls: [LayerKind] = [.knob, .fader, .slider, .meter, .toggle, .control]
    private let shapes: [ShapeKind] = [.rectangle, .roundedRectangle, .ellipse, .capsule, .star, .divider, .card, .glassPanel, .callout]

    var body: some View {
        Menu {
            Section("Layout") { menuButtons(layout) }
            Section("Content") { menuButtons(content) }
            Section("Shapes") {
                ForEach(Array(shapes.enumerated()), id: \.offset) { _, s in
                    Button(s.displayName) { store.addShape(s) }
                }
                Button("Line") { store.addLine() }
                Button("Polygon") { store.addPolygon() }
                Button("Star") { store.addPolygon(sides: 5, star: true) }
                Button("Gradient") { store.addGradient() }
            }
            Section("Plugin Controls") { menuButtons(controls) }
        } label: {
            Label("Add Layer", systemImage: "plus")
        }
        .help("Add a layer")
    }

    @ViewBuilder
    private func menuButtons(_ kinds: [LayerKind]) -> some View {
        ForEach(Array(kinds.enumerated()), id: \.offset) { _, kind in
            Button(kind.displayName) { store.addLayer(kind) }
        }
    }
}
