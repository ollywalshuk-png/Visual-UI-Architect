import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RepositoryEngine

/// "Import Existing UI" panel (Phase 18). Choose a SwiftUI file or an app/repo
/// folder, see detected view candidates with confidence + warnings, and import
/// the selected one into the canvas as editable layers.
struct ImportUIView: View {
    @EnvironmentObject var store: DocumentStore
    @Environment(\.dismiss) private var dismiss

    @State private var candidates: [ExistingUIImport.Candidate] = []
    @State private var selection: ExistingUIImport.Candidate.ID?
    @State private var scannedLabel: String = ""
    @State private var project: ExistingUIImport.ProjectInfo?
    @State private var previewSource: String = ""
    @State private var importTemporaryLayers = false

    private var selected: ExistingUIImport.Candidate? {
        candidates.first { $0.id == selection }
    }

    private var canImportSelected: Bool {
        guard let selected else { return false }
        return selected.hasAnchors || importTemporaryLayers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Import Existing UI", systemImage: "square.and.arrow.down.on.square").font(.headline)
                Spacer()
                Button { chooseFile() } label: { Label("Choose File…", systemImage: "doc") }
                Button { chooseFolder() } label: { Label("Choose Folder…", systemImage: "folder") }
            }
            .padding()
            Divider()

            if candidates.isEmpty {
                ContentUnavailableViewCompat(
                    title: "No Views Yet",
                    systemImage: "rectangle.dashed.badge.record",
                    description: "Choose a SwiftUI file or an app/repo folder to detect importable screens.")
            } else {
                HSplitView {
                    candidateList.frame(minWidth: 240)
                    detailPane.frame(minWidth: 280)
                }
            }

            Divider()
            HStack {
                if !scannedLabel.isEmpty {
                    Text(scannedLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button(selected?.hasAnchors == false ? "Import Temporary Layers" : "Import") {
                    if let selected, store.importExistingUI(selected) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canImportSelected)
            }
            .padding()
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    // MARK: - Panes

    private var candidateList: some View {
        List(selection: $selection) {
            if let project { projectSection(project) }
            Section("Detected Views (\(candidates.count))") {
                ForEach(candidates) { c in
                    HStack(spacing: 8) {
                        Image(systemName: c.isPreviewOnly ? "eye.slash" : "rectangle.on.rectangle")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.viewName).fontWeight(.medium)
                            Text(URL(fileURLWithPath: c.filePath).lastPathComponent)
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        confidenceBadge(c.confidence)
                    }
                    .tag(c.id)
                }
            }
        }
        .onChange(of: selection) { _, _ in loadPreview() }
    }

    @ViewBuilder
    private func projectSection(_ p: ExistingUIImport.ProjectInfo) -> some View {
        Section("Project") {
            if p.hasPackageSwift { row("Package.swift", "found") }
            if !p.xcodeProjects.isEmpty { row(".xcodeproj", p.xcodeProjects.joined(separator: ", ")) }
            if !p.xcworkspaces.isEmpty { row(".xcworkspace", p.xcworkspaces.joined(separator: ", ")) }
            if !p.uiDirectories.isEmpty { row("UI folders", p.uiDirectories.joined(separator: ", ")) }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v).font(.caption) }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let c = selected {
            VStack(alignment: .leading, spacing: 8) {
                Text(c.viewName).font(.title3.bold())
                Text(c.filePath).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                HStack(spacing: 12) {
                    stat("Confidence", "\(Int(c.confidence * 100))%")
                    stat("Supported", "\(c.supportedElementCount)")
                    stat("Unsupported", "\(c.unsupportedElementCount)")
                    stat("Anchors", c.hasAnchors ? "yes" : "no")
                }
                if !c.hasAnchors {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("No source anchors were found. Import will be editable on the canvas, but Apply to Source will be blocked until the source has accessibilityIdentifier anchors and is re-imported.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Toggle("Import as editable temporary layers", isOn: $importTemporaryLayers)
                            .toggleStyle(.checkbox)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                }
                if !c.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(c.warnings.enumerated()), id: \.offset) { _, w in
                            Label(w, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                Divider()
                HStack {
                    Text("Source preview").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !previewSource.isEmpty {
                        Text("\(previewSource.split(separator: "\n", omittingEmptySubsequences: false).count) lines")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                ScrollView {
                    Text(previewSource)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding()
        } else {
            ContentUnavailableViewCompat(title: "Select a View",
                                         systemImage: "sidebar.right",
                                         description: "Pick a detected view to preview and import.")
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).fontWeight(.semibold)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func confidenceBadge(_ c: Double) -> some View {
        Text("\(Int(c * 100))%")
            .font(.caption2.bold())
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background((c >= 0.75 ? Color.green : c >= 0.4 ? Color.orange : Color.red).opacity(0.25), in: Capsule())
    }

    // MARK: - Actions

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.swiftSource]
        panel.allowsMultipleSelection = false
        panel.title = "Choose a SwiftUI file"
        if panel.runModal() == .OK, let url = panel.url {
            candidates = store.scanForImportCandidates(file: url)
            project = nil
            scannedLabel = "\(candidates.count) view(s) in \(url.lastPathComponent)"
            selectFirst()
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose an app/repo folder"
        if panel.runModal() == .OK, let url = panel.url {
            candidates = store.scanForImportCandidates(repo: url)
            project = store.detectProject(at: url)
            scannedLabel = "\(candidates.count) view(s) in \(url.lastPathComponent)"
            selectFirst()
        }
    }

    private func selectFirst() {
        selection = candidates.first(where: { !$0.isPreviewOnly })?.id ?? candidates.first?.id
        importTemporaryLayers = false
        loadPreview()
    }

    private func loadPreview() {
        importTemporaryLayers = false
        guard let c = selected,
              let source = try? String(contentsOf: URL(fileURLWithPath: c.filePath), encoding: .utf8) else {
            previewSource = ""
            return
        }
        previewSource = source
    }
}
