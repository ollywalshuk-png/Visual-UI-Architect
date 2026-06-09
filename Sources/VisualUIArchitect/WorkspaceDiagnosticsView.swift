import SwiftUI
import WorkspaceEngine

/// Workspace safety diagnostics — shows the resolved repo/app/target context
/// and any warnings before the user applies, exports, or commits.
struct WorkspaceDiagnosticsView: View {
    @EnvironmentObject var store: DocumentStore
    @Environment(\.dismiss) private var dismiss
    @State private var context: WorkspaceContext?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Workspace Diagnostics", systemImage: "checkmark.shield").font(.headline)
                Spacer()
                if let c = context {
                    Label("Confidence \(Int(c.confidence * 100))%",
                          systemImage: c.isSafeToWrite ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .foregroundStyle(c.isSafeToWrite ? .green : .red)
                }
            }
            .padding()
            Divider()

            if let c = context {
                ScrollView { content(c).padding() }
            } else {
                ContentUnavailableViewCompat(
                    title: "No Workspace",
                    systemImage: "folder.badge.questionmark",
                    description: "Open a repository or a source file to resolve workspace safety.")
            }

            Divider()
            HStack {
                Button { context = store.refreshWorkspace() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding()
        }
        .frame(minWidth: 560, minHeight: 460)
        .onAppear { context = store.refreshWorkspace() }
    }

    private func content(_ c: WorkspaceContext) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            group("Repository") {
                row("Root", c.rootURL.path)
                row("Git repo", c.isGitRepo ? "yes" : "no")
                if let b = c.branch { row("Branch", c.detachedHEAD ? "\(b) (detached)" : b) }
                if let commit = c.latestCommit { row("Commit", commit) }
                row("Working tree", c.isDirty ? "dirty" : "clean")
                if let op = c.operationInProgress { row("In progress", op) }
            }
            group("Targets") {
                row("Package.swift", "\(c.packageManifests.count)")
                row(".xcodeproj", "\(c.xcodeProjects.count)")
                row(".xcworkspace", "\(c.xcodeWorkspaces.count)")
                row("Nested repos", "\(c.nestedGitRepos.count)")
                row("Swift files", "\(c.swiftFileCount)")
                row("SwiftUI views", "\(c.uiSourceCount)")
            }
            group("Classification") {
                row("Generated export", c.looksLikeGeneratedExport ? "⚠︎ yes" : "no")
                row("Build folder", c.looksLikeBuildFolder ? "⚠︎ yes" : "no")
                row("Dependency folder", c.looksLikeDependencyFolder ? "⚠︎ yes" : "no")
                row("Safe to write", c.isSafeToWrite ? "yes" : "no")
            }
            if !c.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Diagnostics").font(.headline)
                    ForEach(c.warnings) { w in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: icon(w.severity)).foregroundStyle(color(w.severity))
                            Text(w.message)
                            Spacer()
                            Text(w.code.rawValue).font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); c() }
    }
    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).frame(width: 140, alignment: .leading).foregroundStyle(.secondary); Text(v).textSelection(.enabled); Spacer() }
            .font(.callout)
    }
    private func icon(_ s: WorkspaceWarning.Severity) -> String {
        [ "info.circle", "exclamationmark.triangle.fill", "xmark.octagon.fill" ][s.rawValue]
    }
    private func color(_ s: WorkspaceWarning.Severity) -> Color {
        [Color.secondary, .orange, .red][s.rawValue]
    }
}
