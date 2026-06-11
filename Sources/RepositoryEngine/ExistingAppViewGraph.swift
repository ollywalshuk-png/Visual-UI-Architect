import Foundation
import VUACore

public struct ExistingAppViewGraph: Sendable, Hashable {
    public struct Node: Identifiable, Sendable, Hashable {
        public enum Kind: String, Sendable { case app, view, component, dependency }
        public var id: String
        public var title: String
        public var kind: Kind
        public var sourceFile: String?
    }

    public struct Edge: Sendable, Hashable {
        public enum Kind: String, Sendable { case hierarchy, component, dependency }
        public var from: String
        public var to: String
        public var kind: Kind
    }

    public struct Diagnostic: Sendable, Hashable, Identifiable {
        public enum Severity: String, Sendable { case info, warning }
        public let id = UUID()
        public var severity: Severity
        public var message: String
    }

    public var nodes: [Node]
    public var edges: [Edge]
    public var diagnostics: [Diagnostic]

    public struct Stats: Sendable, Hashable {
        public var viewCount: Int
        public var componentCount: Int
        public var dependencyCount: Int
        public var edgeCount: Int
    }

    public var stats: Stats {
        Stats(viewCount: nodes.filter { $0.kind == .view }.count,
              componentCount: nodes.filter { $0.kind == .component }.count,
              dependencyCount: nodes.filter { $0.kind == .dependency }.count,
              edgeCount: edges.count)
    }

    public func search(_ query: String) -> [Node] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return nodes }
        return nodes.filter {
            $0.title.lowercased().contains(q) || ($0.sourceFile?.lowercased().contains(q) ?? false)
        }
    }

    public func sourceFile(for nodeID: String) -> String? {
        nodes.first { $0.id == nodeID }?.sourceFile
    }

    public func outgoing(from nodeID: String) -> [Node] {
        let targets = Set(edges.filter { $0.from == nodeID }.map(\.to))
        return nodes.filter { targets.contains($0.id) }.sorted { $0.title < $1.title }
    }
}

public enum ExistingAppViewGraphBuilder {
    public static func build(repoRoot: URL, files: [RepositoryFile], document: Document? = nil) -> ExistingAppViewGraph {
        var nodes: [ExistingAppViewGraph.Node] = [
            .init(id: "app", title: repoRoot.lastPathComponent.isEmpty ? "App" : repoRoot.lastPathComponent,
                  kind: .app, sourceFile: nil)
        ]
        var edges: [ExistingAppViewGraph.Edge] = []
        var diagnostics: [ExistingAppViewGraph.Diagnostic] = []
        let viewFiles = files.filter { $0.role == .swiftUIView }
        var viewToFile: [String: RepositoryFile] = [:]

        for file in viewFiles {
            for view in file.viewNames {
                let id = "view:\(view)"
                viewToFile[view] = file
                nodes.append(.init(id: id, title: view, kind: .view, sourceFile: file.absolutePath))
                edges.append(.init(from: "app", to: id, kind: .hierarchy))
            }
        }

        for file in viewFiles {
            guard let source = try? String(contentsOfFile: file.absolutePath, encoding: .utf8) else {
                diagnostics.append(.init(severity: .warning, message: "Could not read \(file.relativePath)."))
                continue
            }
            for parent in file.viewNames {
                for child in viewToFile.keys where child != parent && source.contains("\(child)(") {
                    edges.append(.init(from: "view:\(parent)", to: "view:\(child)", kind: .hierarchy))
                }
            }
            for dependency in importedModules(in: source) {
                let id = "dependency:\(dependency)"
                if !nodes.contains(where: { $0.id == id }) {
                    nodes.append(.init(id: id, title: dependency, kind: .dependency, sourceFile: file.absolutePath))
                }
                for view in file.viewNames {
                    edges.append(.init(from: "view:\(view)", to: id, kind: .dependency))
                }
            }
        }

        if let document {
            for component in document.components {
                let id = "component:\(component.id.uuidString)"
                nodes.append(.init(id: id, title: component.name, kind: .component, sourceFile: nil))
                edges.append(.init(from: "app", to: id, kind: .component))
            }
        }

        if viewFiles.isEmpty {
            diagnostics.append(.init(severity: .info, message: "No SwiftUI view files found."))
        }
        if nodes.count > 250 || edges.count > 500 {
            diagnostics.append(.init(severity: .warning,
                                     message: "Large graph: \(nodes.count) nodes and \(edges.count) edges. Use search to narrow navigation."))
        }
        return ExistingAppViewGraph(nodes: nodes, edges: Array(Set(edges)), diagnostics: diagnostics)
    }

    private static func importedModules(in source: String) -> [String] {
        source.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("import ") else { return nil }
            let name = trimmed.dropFirst("import ".count).split(separator: " ").first.map(String.init)
            return name == "SwiftUI" ? nil : name
        }
    }
}
