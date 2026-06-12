import SwiftUI
import VUACore
import RepositoryEngine
import CodeGenEngine

struct TargetInjectionView: View {
    @EnvironmentObject var store: DocumentStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPath = ""
    @State private var newFilePath = "Sources/App/GeneratedScreen.swift"
    @State private var createNewFile = false
    @State private var allowDirtyRepo = false
    @State private var allowFullFileReplacement = false
    @State private var runBuild = true
    @State private var copyReferencedAssets = false
    @State private var assetDestinationDirectory = "Resources"
    @State private var result: TargetAppInjection.Result?

    private var swiftFiles: [RepositoryFile] {
        store.repositoryFiles.filter { $0.role == .swiftUIView || $0.role == .swiftSource }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Form {
                Section("Target") {
                    Toggle("Create new Swift file", isOn: $createNewFile)
                    if createNewFile {
                        TextField("Sources/App/GeneratedScreen.swift", text: $newFilePath)
                    } else {
                        Picker("File", selection: $selectedPath) {
                            Text("Select target").tag("")
                            ForEach(swiftFiles) { file in Text(file.relativePath).tag(file.relativePath) }
                        }
                    }
                    Toggle("Allow dirty repository", isOn: $allowDirtyRepo)
                    Toggle("Allow full-file replacement", isOn: $allowFullFileReplacement)
                        .disabled(createNewFile)
                    Toggle("Run swift build after apply", isOn: $runBuild)
                }
                Section("Assets") {
                    Toggle("Copy referenced assets", isOn: $copyReferencedAssets)
                    if copyReferencedAssets {
                        TextField("Resources", text: $assetDestinationDirectory)
                    }
                }
                if let result {
                    Section("Result") {
                        Label(result.summary, systemImage: result.hasBlocker ? "xmark.octagon" : "checkmark.circle")
                            .foregroundStyle(result.hasBlocker ? .red : .green)
                        LabeledContent("Target") { Text(result.targetURL.path).lineLimit(2).truncationMode(.middle) }
                        LabeledContent("Assets") { Text(result.assetDependencies.isEmpty ? "none" : result.assetDependencies.joined(separator: ", ")) }
                        if !result.assetCopyResults.isEmpty {
                            LabeledContent("Asset copies") {
                                Text(result.assetCopyResults.map(\.destinationRelativePath).joined(separator: ", "))
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                            }
                        }
                        LabeledContent("Rollback") { Text(result.rollbackPlan.joined(separator: "  |  ")).textSelection(.enabled) }
                    }
                    if !result.diagnostics.isEmpty {
                        Section("Diagnostics") {
                            ForEach(result.diagnostics) { diagnostic in
                                Label(diagnostic.message, systemImage: icon(diagnostic.severity))
                                    .foregroundStyle(color(diagnostic.severity))
                            }
                        }
                    }
                    Section("Diff") {
                        ScrollView {
                            Text((result.gitDiff.isEmpty ? result.previewDiff : result.gitDiff).isEmpty ? "No diff" : (result.gitDiff.isEmpty ? result.previewDiff : result.gitDiff))
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 180)
                    }
                    if result.buildRan {
                        Section("Build") {
                            Text(result.buildPassed ? "passed" : "failed")
                                .foregroundStyle(result.buildPassed ? .green : .red)
                            if !result.buildOutput.isEmpty {
                                ScrollView {
                                    Text(result.buildOutput)
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                                .frame(minHeight: 120)
                            }
                        }
                    }
                }
            }
            Divider()
            HStack {
                Button("Preview") { run(write: false) }.disabled(!canRun)
                Button("Apply") { run(write: true) }.disabled(!canRun)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 760, minHeight: 620)
        .onAppear {
            if selectedPath.isEmpty { selectedPath = swiftFiles.first?.relativePath ?? "" }
        }
    }

    private var header: some View {
        HStack {
            Label("Target App Injection", systemImage: "arrow.down.doc")
                .font(.headline)
            Spacer()
        }
        .padding()
    }

    private var targetPath: String {
        createNewFile ? newFilePath.trimmingCharacters(in: .whitespacesAndNewlines) : selectedPath
    }

    private var canRun: Bool {
        store.repositoryRoot != nil &&
            !targetPath.isEmpty &&
            (!copyReferencedAssets || !assetDestinationDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func run(write: Bool) {
        guard let root = store.repositoryRoot,
              let generated = try? CodeGenService().generate(store.document).contents else { return }
        let copies = copyReferencedAssets ? assetCopies(for: generated) : []
        let request = TargetAppInjection.Request(
            repoRoot: root,
            targetFile: targetPath,
            generatedSource: generated,
            expectedHash: createNewFile ? nil : currentHash(root: root, path: targetPath),
            allowDirtyRepo: allowDirtyRepo,
            runBuild: runBuild,
            allowFullFileReplacement: !createNewFile && allowFullFileReplacement,
            allowCreateFile: createNewFile,
            assetCopies: copies,
            assetDestinationDirectory: copyReferencedAssets ? assetDestinationDirectory : nil,
            allowAssetCopy: copyReferencedAssets)
        result = write ? TargetAppInjection.apply(request) : TargetAppInjection.preview(request)
    }

    private func assetCopies(for generated: String) -> [TargetAppInjection.AssetCopy] {
        let refs = Set(imageReferences(in: generated).map { $0.lowercased() })
        guard !refs.isEmpty else { return [] }
        return store.document.assets.compactMap { asset in
            guard refs.contains(asset.name.lowercased()) else { return nil }
            return TargetAppInjection.AssetCopy(
                name: asset.name,
                sourceURL: store.assetsDirectory.appendingPathComponent(asset.path),
                destinationFileName: asset.path)
        }
    }

    private func imageReferences(in source: String) -> [String] {
        var out: [String] = []
        let marker = "Image(\""
        var index = source.startIndex
        while let range = source.range(of: marker, range: index..<source.endIndex) {
            let rest = source[range.upperBound...]
            guard let close = rest.firstIndex(of: "\"") else { break }
            let name = String(rest[..<close])
            if !out.contains(name) { out.append(name) }
            index = close
        }
        return out
    }

    private func currentHash(root: URL, path: String) -> String? {
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return SourceSafety.hash(of: source)
    }

    private func icon(_ severity: TargetAppInjection.Diagnostic.Severity) -> String {
        switch severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .blocker: return "xmark.octagon"
        }
    }

    private func color(_ severity: TargetAppInjection.Diagnostic.Severity) -> Color {
        switch severity {
        case .info: return .blue
        case .warning: return .orange
        case .blocker: return .red
        }
    }
}
