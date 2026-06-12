import Foundation
import RepositoryEngine
import VUACore

public enum AppleUIImport {
    public static func scanRepository(_ root: URL, framework: ImportFramework) -> [ExistingUIImport.Candidate] {
        let fm = FileManager.default
        let skip: Set<String> = [".git", ".build", ".swiftpm", "DerivedData", "Pods", "node_modules"]
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var candidates: [ExistingUIImport.Candidate] = []
        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                if skip.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            guard url.pathExtension == "swift",
                  let source = try? String(contentsOf: url, encoding: .utf8),
                  isFrameworkSource(source, framework: framework) else { continue }
            candidates.append(contentsOf: self.candidates(
                inSource: source,
                filePath: url.path,
                repoRoot: root.path,
                framework: framework))
        }
        return candidates.sorted { lhs, rhs in
            if lhs.confidence == rhs.confidence { return lhs.viewName < rhs.viewName }
            return lhs.confidence > rhs.confidence
        }
    }

    public static func candidates(inSource source: String, filePath: String,
                                  repoRoot: String? = nil,
                                  framework: ImportFramework) -> [ExistingUIImport.Candidate] {
        guard isFrameworkSource(source, framework: framework) else { return [] }
        return viewClasses(in: source, framework: framework).compactMap { viewClass in
            let result = AppleLayerMapper(filePath: filePath, framework: framework)
                .map(source: viewClass.body, rootName: viewClass.name)
            guard result.supported + result.unsupported > 0 else { return nil }

            var warnings = ["Static \(framework.displayName) import: imperative view setup and direct frames are editable; constraints, target/action handlers, delegates, and runtime state remain source-owned."]
            if result.unsupported > 0 {
                warnings.append("\(result.unsupported) unsupported \(framework.displayName) view(s) will import as locked placeholders.")
            }
            if !result.hasAnchors {
                warnings.append("No accessibilityIdentifier/identifier anchors were found; imported layers are editable but source apply remains limited.")
            }

            let total = result.supported + result.unsupported
            return ExistingUIImport.Candidate(
                viewName: viewClass.name,
                filePath: filePath,
                repoRoot: repoRoot,
                confidence: total == 0 ? 0 : Double(result.supported) / Double(total),
                supportedElementCount: result.supported,
                unsupportedElementCount: result.unsupported,
                hasAnchors: result.hasAnchors,
                isPreviewOnly: false,
                warnings: warnings)
        }
    }

    public static func importCandidate(_ candidate: ExistingUIImport.Candidate) -> ExistingUIImport.Imported? {
        let url = URL(fileURLWithPath: candidate.filePath)
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let framework: ImportFramework
        if source.contains("import UIKit") {
            framework = .uiKit
        } else if source.contains("import AppKit") {
            framework = .appKit
        } else {
            return nil
        }
        guard let viewClass = viewClasses(in: source, framework: framework)
            .first(where: { $0.name == candidate.viewName }) else { return nil }
        let result = AppleLayerMapper(filePath: candidate.filePath, framework: framework)
            .map(source: viewClass.body, rootName: viewClass.name)
        guard !result.layers.isEmpty else { return nil }
        return ExistingUIImport.Imported(
            view: ParsedView(typeName: candidate.viewName, roots: result.layers, filePath: candidate.filePath),
            sourceHash: ExistingUIImport.sourceHash(source),
            hasAnchors: false)
    }

    private static func isFrameworkSource(_ source: String, framework: ImportFramework) -> Bool {
        switch framework {
        case .uiKit:
            return source.contains("import UIKit")
        case .appKit:
            return source.contains("import AppKit")
        default:
            return false
        }
    }

    private static func viewClasses(in source: String, framework: ImportFramework) -> [AppleViewClass] {
        let superclassPattern: String
        switch framework {
        case .uiKit:
            superclassPattern = #"(?:UIViewController|UITableViewController|UICollectionViewController|UIView)"#
        case .appKit:
            superclassPattern = #"(?:NSViewController|NSWindowController|NSView)"#
        default:
            return []
        }
        guard let regex = try? NSRegularExpression(
            pattern: #"\b(?:final\s+)?class\s+([A-Z][A-Za-z0-9_]*)\s*:\s*\#(superclassPattern)[^{]*\{"#,
            options: []
        ) else { return [] }
        let ns = source as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.matches(in: source, options: [], range: range).compactMap { match in
            guard let nameRange = Range(match.range(at: 1), in: source),
                  let matchRange = Range(match.range, in: source) else { return nil }
            let openBrace = source.index(before: matchRange.upperBound)
            guard let closeBrace = matchingBrace(in: source, open: openBrace) else { return nil }
            return AppleViewClass(
                name: String(source[nameRange]),
                body: String(source[source.index(after: openBrace)..<closeBrace]))
        }
    }

    private static func matchingBrace(in source: String, open: String.Index) -> String.Index? {
        var depth = 0
        var quote: Character?
        var escaped = false
        var index = open
        while index < source.endIndex {
            let character = source[index]
            if let currentQuote = quote {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == currentQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = source.index(after: index)
        }
        return nil
    }
}

private struct AppleViewClass {
    var name: String
    var body: String
}

private struct AppleLayerResult {
    var layers: [Layer]
    var supported: Int
    var unsupported: Int
    var hasAnchors: Bool
}

private struct AppleViewObject {
    var variableName: String
    var typeName: String
    var kind: LayerKind
    var name: String
    var frame: VRect?
    var text: String?
    var anchorID: String?
    var fontSize: Double?
    var isLocked: Bool
    var notes: String?
}

private struct AppleLayerMapper {
    let filePath: String
    let framework: ImportFramework

    func map(source: String, rootName: String) -> AppleLayerResult {
        var objects = declaredObjects(in: source)
        applyAssignments(in: source, to: &objects)
        let edges = addSubviewEdges(in: source, objectNames: Set(objects.keys))

        var childNames = Set<String>()
        for (parent, children) in edges where parent != "__root__" {
            childNames.formUnion(children)
        }

        let fallbackRoots = orderedObjects(in: objects)
            .map(\.variableName)
            .filter { !childNames.contains($0) }
        let rootChildren = edges["__root__"] ?? fallbackRoots
        var built: Set<String> = []
        let layers = rootChildren.compactMap { buildLayer($0, objects: objects, edges: edges, built: &built) }
        let supported = objects.values.filter { !$0.isLocked }.count
        let unsupported = objects.values.filter(\.isLocked).count
        let hasAnchors = objects.values.contains { $0.anchorID != nil }

        guard !layers.isEmpty else {
            return AppleLayerResult(layers: [], supported: supported, unsupported: unsupported, hasAnchors: hasAnchors)
        }

        var root = Layer(
            name: rootName,
            kind: .container,
            frame: VRect(x: 24, y: 24, width: 640, height: max(240, Double(layers.count) * 72 + 32)),
            notes: "Imported from \(framework.displayName) imperative view setup. Source write-back is disabled for this framework in this pass.",
            tags: ["import:apple-ui", "framework:\(framework.rawValue)"],
            children: layers)
        layoutChildren(of: &root)
        return AppleLayerResult(layers: [root], supported: supported, unsupported: unsupported, hasAnchors: hasAnchors)
    }

    private func declaredObjects(in source: String) -> [String: AppleViewObject] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b(?:private\s+|fileprivate\s+|public\s+|internal\s+|lazy\s+|static\s+)*?(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*([A-Za-z_][A-Za-z0-9_]*))?\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(([^\n;]*)\)"#,
            options: []
        ) else { return [:] }
        let ns = source as NSString
        let range = NSRange(location: 0, length: ns.length)
        var objects: [String: AppleViewObject] = [:]
        for match in regex.matches(in: source, options: [], range: range) {
            let variable = ns.substring(with: match.range(at: 1))
            let explicitType = match.range(at: 2).location == NSNotFound ? nil : ns.substring(with: match.range(at: 2))
            let constructor = ns.substring(with: match.range(at: 3))
            let typeName = explicitType ?? constructor
            let args = ns.substring(with: match.range(at: 4))
            guard let object = object(variable: variable, typeName: typeName, constructorArguments: args) else { continue }
            objects[variable] = object
        }
        return objects
    }

    private func object(variable: String, typeName: String, constructorArguments args: String) -> AppleViewObject? {
        guard let mapping = kind(for: typeName) else { return nil }
        var name = readableName(variable)
        let text = textFromConstructor(typeName: typeName, arguments: args)
        if let text { name = text }
        let locked = mapping.isLocked
        let notes = locked
            ? "\(typeName) is preserved as a locked \(framework.displayName) placeholder because custom view behaviour cannot be safely edited yet."
            : nil
        return AppleViewObject(
            variableName: variable,
            typeName: typeName,
            kind: mapping.kind,
            name: name,
            frame: nil,
            text: text,
            anchorID: nil,
            fontSize: nil,
            isLocked: locked,
            notes: notes)
    }

    private func kind(for typeName: String) -> (kind: LayerKind, isLocked: Bool)? {
        switch framework {
        case .uiKit:
            switch typeName {
            case "UIView", "UIStackView", "UIScrollView", "UITableView", "UICollectionView":
                return (.container, false)
            case "UILabel":
                return (.label, false)
            case "UIButton":
                return (.button, false)
            case "UISlider":
                return (.slider, false)
            case "UISwitch":
                return (.toggle, false)
            case "UITextField", "UITextView":
                return (.text, false)
            case "UIImageView":
                return (.image, false)
            case "UISegmentedControl", "UIControl":
                return (.control, false)
            default:
                return typeName.hasSuffix("View") || typeName.hasSuffix("Control") ? (.custom(typeName: typeName), true) : nil
            }
        case .appKit:
            switch typeName {
            case "NSView", "NSStackView", "NSScrollView":
                return (.container, false)
            case "NSBox":
                return (.panel, false)
            case "NSTextField":
                return (.label, false)
            case "NSButton":
                return (.button, false)
            case "NSSlider":
                return (.slider, false)
            case "NSSwitch", "NSButtonCheckbox":
                return (.toggle, false)
            case "NSTextView":
                return (.text, false)
            case "NSImageView":
                return (.image, false)
            case "NSComboBox", "NSPopUpButton":
                return (.control, false)
            default:
                return typeName.hasSuffix("View") || typeName.hasSuffix("Control") ? (.custom(typeName: typeName), true) : nil
            }
        default:
            return nil
        }
    }

    private func applyAssignments(in source: String, to objects: inout [String: AppleViewObject]) {
        for variable in Array(objects.keys) {
            if let frame = frameAssignment(for: variable, in: source) {
                objects[variable]?.frame = frame
            }
            if let anchor = anchorAssignment(for: variable, in: source) {
                objects[variable]?.anchorID = anchor
                objects[variable]?.name = anchor
            }
            if let text = textAssignment(for: variable, in: source) {
                objects[variable]?.text = text
                if objects[variable]?.anchorID == nil {
                    objects[variable]?.name = text
                }
            }
            if let fontSize = fontSizeAssignment(for: variable, in: source) {
                objects[variable]?.fontSize = fontSize
            }
        }
    }

    private func addSubviewEdges(in source: String, objectNames: Set<String>) -> [String: [String]] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b((?:self\.)?[A-Za-z_][A-Za-z0-9_]*(?:\?)?)\.addSubview\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)"#,
            options: []
        ) else { return [:] }
        let ns = source as NSString
        let range = NSRange(location: 0, length: ns.length)
        var edges: [String: [String]] = [:]
        var rootOrder: [String] = []
        for match in regex.matches(in: source, options: [], range: range) {
            let rawParent = ns.substring(with: match.range(at: 1))
                .replacingOccurrences(of: "self.", with: "")
                .replacingOccurrences(of: "?", with: "")
            let child = ns.substring(with: match.range(at: 2))
            guard objectNames.contains(child) else { continue }
            if objectNames.contains(rawParent) {
                edges[rawParent, default: []].append(child)
            } else if ["view", "contentView"].contains(rawParent) {
                rootOrder.append(child)
            }
        }
        if !rootOrder.isEmpty {
            edges["__root__"] = rootOrder
        }
        return edges
    }

    private func buildLayer(_ name: String, objects: [String: AppleViewObject],
                            edges: [String: [String]], built: inout Set<String>) -> Layer? {
        guard !built.contains(name), let object = objects[name] else { return nil }
        built.insert(name)
        let children = (edges[name] ?? []).compactMap { buildLayer($0, objects: objects, edges: edges, built: &built) }
        var style = LayerStyle.default
        style.fontSize = object.fontSize
        return Layer(
            name: object.name,
            kind: object.kind,
            frame: object.frame ?? VRect(origin: .zero, size: defaultSize(for: object.kind, childCount: children.count)),
            style: style,
            text: textForLayer(kind: object.kind, fallback: object.text),
            isLocked: object.isLocked,
            binding: object.anchorID.map { CodeBinding(filePath: filePath, anchorID: $0) },
            notes: object.notes,
            tags: ["import:apple-ui", "framework:\(framework.rawValue)", "type:\(object.typeName)"],
            children: children)
    }

    private func orderedObjects(in objects: [String: AppleViewObject]) -> [AppleViewObject] {
        objects.values.sorted { $0.variableName < $1.variableName }
    }

    private func textFromConstructor(typeName: String, arguments: String) -> String? {
        switch typeName {
        case "NSTextField":
            return firstMatch(in: arguments, pattern: #"labelWithString\s*:\s*"([^"]+)""#)
        case "NSButton":
            return firstMatch(in: arguments, pattern: #"title\s*:\s*"([^"]+)""#)
        default:
            return nil
        }
    }

    private func frameAssignment(for variable: String, in source: String) -> VRect? {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b\#(variable)\.frame\s*=\s*(?:CGRect|NSRect)\s*\(\s*x\s*:\s*(-?[0-9]+(?:\.[0-9]+)?)\s*,\s*y\s*:\s*(-?[0-9]+(?:\.[0-9]+)?)\s*,\s*width\s*:\s*([0-9]+(?:\.[0-9]+)?)\s*,\s*height\s*:\s*([0-9]+(?:\.[0-9]+)?)"#,
            options: []
        ) else { return nil }
        let ns = source as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: source, options: [], range: range) else { return nil }
        return VRect(
            x: Double(ns.substring(with: match.range(at: 1))) ?? 0,
            y: Double(ns.substring(with: match.range(at: 2))) ?? 0,
            width: Double(ns.substring(with: match.range(at: 3))) ?? 120,
            height: Double(ns.substring(with: match.range(at: 4))) ?? 44)
    }

    private func anchorAssignment(for variable: String, in source: String) -> String? {
        firstMatch(in: source, pattern: #"\b\#(variable)\.accessibilityIdentifier\s*=\s*"([^"]+)""#)
            ?? firstMatch(in: source, pattern: #"\b\#(variable)\.identifier\s*=\s*(?:NSUserInterfaceItemIdentifier|\.init)\s*\(\s*"([^"]+)""#)
            ?? firstMatch(in: source, pattern: #"\b\#(variable)\.identifier\s*=\s*NSUserInterfaceItemIdentifier\s*\(\s*rawValue\s*:\s*"([^"]+)""#)
    }

    private func textAssignment(for variable: String, in source: String) -> String? {
        firstMatch(in: source, pattern: #"\b\#(variable)\.(?:text|stringValue|placeholder|placeholderString|title)\s*=\s*"([^"]+)""#)
            ?? firstMatch(in: source, pattern: #"\b\#(variable)\.setTitle\s*\(\s*"([^"]+)""#)
    }

    private func fontSizeAssignment(for variable: String, in source: String) -> Double? {
        guard let value = firstMatch(
            in: source,
            pattern: #"\b\#(variable)\.font\s*=\s*(?:UIFont|NSFont|\.)?\.?systemFont\s*\(\s*ofSize\s*:\s*([0-9]+(?:\.[0-9]+)?)"#
        ) else { return nil }
        return Double(value)
    }

    private func firstMatch(in source: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = source as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: source, options: [], range: range),
              match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func layoutChildren(of layer: inout Layer) {
        guard !layer.children.isEmpty else { return }
        var y: Double = 16
        var maxWidth: Double = layer.frame.width
        for index in layer.children.indices {
            if layer.children[index].frame.origin == .zero {
                layer.children[index].frame.origin = VPoint(x: 16, y: y)
            }
            layoutChildren(of: &layer.children[index])
            y = max(y, layer.children[index].frame.maxY + 12)
            maxWidth = max(maxWidth, layer.children[index].frame.maxX + 16)
        }
        layer.frame.size.width = max(layer.frame.width, maxWidth)
        layer.frame.size.height = max(layer.frame.height, y + 4)
    }

    private func textForLayer(kind: LayerKind, fallback: String?) -> String? {
        switch kind {
        case .button, .label, .text, .toggle, .control:
            return fallback
        default:
            return nil
        }
    }

    private func defaultSize(for kind: LayerKind, childCount: Int) -> VSize {
        switch kind {
        case .container, .panel, .group, .background:
            return VSize(width: 320, height: max(120, Double(childCount) * 56 + 32))
        case .button:
            return VSize(width: 140, height: 44)
        case .label:
            return VSize(width: 180, height: 28)
        case .text:
            return VSize(width: 180, height: 36)
        case .image:
            return VSize(width: 160, height: 100)
        case .slider:
            return VSize(width: 180, height: 32)
        case .toggle:
            return VSize(width: 140, height: 32)
        case .control, .custom:
            return VSize(width: 180, height: 44)
        default:
            return VSize(width: 120, height: 80)
        }
    }

    private func readableName(_ raw: String) -> String {
        let words = raw
            .replacingOccurrences(of: #"([a-z0-9])([A-Z])"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty ? raw : words.prefix(1).uppercased() + words.dropFirst()
    }
}
