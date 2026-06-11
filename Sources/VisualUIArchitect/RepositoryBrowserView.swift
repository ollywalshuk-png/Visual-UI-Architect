import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RepositoryEngine

/// Repository browser: open a folder, see its SwiftUI views / sources / assets,
/// and open a view into the canvas.
struct RepositoryBrowserView: View {
    @EnvironmentObject var store: DocumentStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { openRepository() } label: { Label("Open Repo", systemImage: "folder") }
                Button { openFile() } label: { Label("Open File", systemImage: "doc") }
                Spacer()
            }
            .padding(8)
            Divider()

            if store.repositoryFiles.isEmpty {
                ContentUnavailableViewCompat(
                    title: "No Repository",
                    systemImage: "folder.badge.questionmark",
                    description: "Open a folder to browse SwiftUI views and assets.")
            } else {
                List {
                    importedSourceSection
                    section("SwiftUI Views", role: .swiftUIView, icon: "rectangle.3.group")
                    section("Sources", role: .swiftSource, icon: "swift")
                    section("Assets", role: .asset, icon: "photo")
                }
                .listStyle(.sidebar)
            }

            if !store.repositoryStatus.isEmpty {
                Divider()
                Text(store.repositoryStatus)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        }
    }

    @ViewBuilder
    private var importedSourceSection: some View {
        if let path = store.importedSourcePath {
            Section("Imported Source") {
                VStack(alignment: .leading, spacing: 4) {
                    Label(store.importedViewName ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                          systemImage: store.importedSourceHasAnchors == false ? "link.badge.plus" : "link")
                        .fontWeight(.medium)
                    Text(path).font(.caption2).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                    HStack {
                        Text(store.importedSourceHasAnchors == false ? "Temporary layers, no anchors" : "Anchored for safe apply")
                            .font(.caption2)
                            .foregroundStyle(store.importedSourceHasAnchors == false ? .orange : .green)
                        if let date = store.importedAt {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, role: RepositoryFile.Role, icon: String) -> some View {
        let files = store.repositoryFiles.filter { $0.role == role }
        if !files.isEmpty {
            Section(title) {
                ForEach(files) { file in
                    HStack {
                        Image(systemName: icon).foregroundStyle(.secondary).frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(URL(fileURLWithPath: file.relativePath).lastPathComponent).lineLimit(1)
                            if !file.viewNames.isEmpty {
                                Text(file.viewNames.joined(separator: ", "))
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        if file.absolutePath == store.importedSourcePath {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(store.importedSourceHasAnchors == false ? .orange : .green)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if role == .swiftUIView { store.openRepositoryFile(file) }
                    }
                }
            }
        }
    }

    // MARK: - Panels

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.swiftSource]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            store.openSwiftUIFile(at: url)
        }
    }

    private func openRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            store.openRepository(at: url)
        }
    }
}
