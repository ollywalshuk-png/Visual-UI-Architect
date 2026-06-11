import SwiftUI
import RepositoryEngine

struct ExistingAppGraphView: View {
    @EnvironmentObject var store: DocumentStore
    @State private var query = ""

    private var graph: ExistingAppViewGraph? {
        guard let root = store.repositoryRoot else { return nil }
        return ExistingAppViewGraphBuilder.build(repoRoot: root, files: store.repositoryFiles, document: store.document)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                Text("View Graph").font(.headline)
                Spacer()
                Text("\(graph?.nodes.count ?? 0)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding([.horizontal, .bottom], 8)
            Divider()
            if let graph {
                List {
                    Section("Hierarchy") {
                        ForEach(graph.search(query).filter { $0.kind == .app || $0.kind == .view }) { node in row(node) }
                    }
                    let components = graph.search(query).filter { $0.kind == .component }
                    if !components.isEmpty {
                        Section("Components") { ForEach(components) { row($0) } }
                    }
                    let deps = graph.search(query).filter { $0.kind == .dependency }
                    if !deps.isEmpty {
                        Section("Dependencies") { ForEach(deps) { row($0) } }
                    }
                    if !graph.diagnostics.isEmpty {
                        Section("Diagnostics") {
                            ForEach(graph.diagnostics) { diagnostic in
                                Label(diagnostic.message, systemImage: diagnostic.severity == .warning ? "exclamationmark.triangle" : "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(diagnostic.severity == .warning ? .orange : .secondary)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            } else {
                ContentUnavailableViewCompat(
                    title: "No Repository",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: "Open a repository to inspect its SwiftUI view graph.")
                    .padding()
            }
        }
    }

    private func row(_ node: ExistingAppViewGraph.Node) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon(node.kind)).foregroundStyle(.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.title).lineLimit(1)
                if let file = node.sourceFile {
                    Text(file).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard node.kind == .view, let file = node.sourceFile else { return }
            let repoFile = RepositoryFile(relativePath: URL(fileURLWithPath: file).lastPathComponent,
                                          absolutePath: file, role: .swiftUIView,
                                          viewNames: [node.title])
            store.openRepositoryFile(repoFile)
        }
    }

    private func icon(_ kind: ExistingAppViewGraph.Node.Kind) -> String {
        switch kind {
        case .app: return "app"
        case .view: return "rectangle.3.group"
        case .component: return "square.on.square"
        case .dependency: return "shippingbox"
        }
    }
}
