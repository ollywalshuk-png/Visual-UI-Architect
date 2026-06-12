import SwiftUI
import AppKit
import VUACore
import ExportIntegrityEngine

/// Export panel: pick a destination, choose options, run the export, and see
/// the integrity report (assets, controls, parameters, diagnostics, files).
struct ExportPanelView: View {
    @EnvironmentObject var store: DocumentStore
    @Environment(\.dismiss) private var dismiss

    @State private var destination: URL?
    @State private var moduleName: String = "GeneratedUI"
    @State private var includeControls: Bool = true
    @State private var includeMultiTargetSources = false
    @State private var result: ExportResult?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Export Integrity", systemImage: "shippingbox")
                    .font(.headline)
                Spacer()
                if let result {
                    Label(result.hasErrors ? "Issues found" : "Ready",
                          systemImage: result.hasErrors ? "xmark.octagon.fill" : "checkmark.seal.fill")
                        .foregroundStyle(result.hasErrors ? .red : .green)
                }
            }
            .padding()
            Divider()

            optionsSection.padding()
            Divider()

            if let result {
                reportView(result)
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).padding()
            } else {
                ContentUnavailableViewCompat(
                    title: "No export yet",
                    systemImage: "shippingbox",
                    description: "Pick a destination and click Export to generate a portable SwiftUI package.")
            }

            Divider()
            HStack {
                if let result {
                    Button { reveal(result.destination) } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(minWidth: 620, minHeight: 520)
    }

    // MARK: - Sections

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Destination").frame(width: 100, alignment: .leading)
                Text(destination?.path ?? "—").lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Choose…") { pickDestination() }
            }
            HStack {
                Text("Module name").frame(width: 100, alignment: .leading)
                TextField("GeneratedUI", text: $moduleName)
                    .textFieldStyle(.roundedBorder).frame(width: 220)
            }
            Toggle("Include VUAControls sources", isOn: $includeControls)
            Toggle("Include multi-target sources", isOn: $includeMultiTargetSources)
            HStack {
                Spacer()
                Button { runExport() } label: { Label("Export", systemImage: "arrow.up.doc.fill") }
                    .keyboardShortcut(.defaultAction)
                    .disabled(destination == nil)
            }
        }
    }

    private func reportView(_ result: ExportResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                section("Files") {
                    fileRow("Generated view", result.generatedCodePath)
                    fileRow("Asset manifest", result.assetManifestPath)
                    fileRow("Parameter manifest", result.parameterManifestPath)
                    fileRow("Export report", result.reportPath)
                }
                if !result.additionalCodeFiles.isEmpty {
                    section("Target sources") {
                        ForEach(Array(result.additionalCodeFiles.enumerated()), id: \.offset) { _, file in
                            HStack {
                                Image(systemName: icon(for: file.target)).foregroundStyle(.secondary)
                                Text(file.target.displayName).frame(width: 140, alignment: .leading)
                                Text(file.relativePath).font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                            }
                        }
                    }
                }
                section("Assets (\(result.assets.count))") {
                    ForEach(Array(result.assets.enumerated()), id: \.offset) { _, asset in
                        HStack {
                            Image(systemName: asset.sourceURL != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(asset.sourceURL != nil ? .green : .red)
                            Text(asset.imageName).font(.system(.body, design: .monospaced))
                            Spacer()
                            Text("Resources/\(asset.exportedFileName)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                section("Controls library") {
                    HStack {
                        Image(systemName: result.includedControlsLibrary ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(result.includedControlsLibrary ? .green : .orange)
                        Text(result.includedControlsLibrary
                             ? "VUAControls sources copied to Sources/VUAControls"
                             : "Manual setup required (see export report)")
                    }
                }
                section("Parameters (\(result.parameters.count))") {
                    ForEach(Array(result.parameters.enumerated()), id: \.offset) { _, p in
                        HStack {
                            Image(systemName: p.isPlaceholder ? "exclamationmark.triangle.fill" : "circle.fill")
                                .foregroundStyle(p.isPlaceholder ? .orange : .secondary)
                                .font(.caption)
                            Text("\(p.parameterID) — \(p.displayName)")
                            Spacer()
                            Text("\(format(p.minValue))…\(format(p.maxValue)) \(p.unit)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !result.diagnostics.isEmpty {
                    section("Diagnostics") {
                        ForEach(Array(result.diagnostics.enumerated()), id: \.offset) { _, d in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: severityIcon(d.severity))
                                    .foregroundStyle(severityColor(d.severity))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.message)
                                    if let detail = d.detail {
                                        Text(detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(d.code.rawValue).font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15), in: Capsule())
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }

    private func fileRow(_ label: String, _ url: URL) -> some View {
        HStack {
            Image(systemName: "doc.text").foregroundStyle(.secondary)
            Text(label).frame(width: 140, alignment: .leading)
            Text(url.lastPathComponent).font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Actions

    private func pickDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        if panel.runModal() == .OK, let url = panel.url {
            destination = url
        }
    }

    private func runExport() {
        guard let destination else { return }
        result = nil; errorMessage = nil
        let exportRoot = destination.appendingPathComponent("\(moduleName)-Export")
        switch store.exportPackage(
            to: exportRoot,
            moduleName: moduleName,
            includeControls: includeControls,
            includeMultiTargetSources: includeMultiTargetSources) {
        case .success(let r): result = r
        case .failure(let error): errorMessage = "\(error)"
        }
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func severityIcon(_ s: ExportDiagnostic.Severity) -> String {
        switch s {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle"
        }
    }

    private func severityColor(_ s: ExportDiagnostic.Severity) -> Color {
        switch s {
        case .error: return .red
        case .warning: return .orange
        case .info: return .secondary
        }
    }

    private func icon(for target: CodeGenTarget) -> String {
        switch target {
        case .swiftUI, .uiKit, .appKit: return "curlybraces"
        case .react, .reactNative: return "atom"
        case .htmlCSS, .electronRenderer: return "globe"
        case .flutter: return "diamond"
        case .jetpackCompose: return "square.stack.3d.up"
        }
    }

    private func format(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.2f", d)
    }
}
