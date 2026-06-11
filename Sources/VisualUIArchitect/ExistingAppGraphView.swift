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
                    Section("Summary") {
                        metrics(graph)
                    }
                    Section("Hierarchy") {
                        ForEach(graph.search(query).filter { $0.kind == .app || $0.kind == .view }) { node in row(node, graph: graph) }
                    }
                    let components = graph.search(query).filter { $0.kind == .component }
                    if !components.isEmpty {
                        Section("Components") { ForEach(components) { row($0, graph: graph) } }
                    }
                    let deps = graph.search(query).filter { $0.kind == .dependency }
                    if !deps.isEmpty {
                        Section("Dependencies") { ForEach(deps) { row($0, graph: graph) } }
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

    private func metrics(_ graph: ExistingAppViewGraph) -> some View {
        HStack {
            metric("Views", graph.stats.viewCount)
            metric("Components", graph.stats.componentCount)
            metric("Deps", graph.stats.dependencyCount)
            metric("Edges", graph.stats.edgeCount)
        }
    }

    private func metric(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)").font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ node: ExistingAppViewGraph.Node, graph: ExistingAppViewGraph) -> some View {
        let outgoing = graph.outgoing(from: node.id)
        return HStack(spacing: 8) {
            Image(systemName: icon(node.kind)).foregroundStyle(.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.title).lineLimit(1)
                if let file = node.sourceFile {
                    Text(file).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                if !outgoing.isEmpty {
                    Text("Links: \(outgoing.prefix(4).map(\.title).joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
