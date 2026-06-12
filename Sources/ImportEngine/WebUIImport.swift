import Foundation
import RepositoryEngine
import VUACore

public enum WebUIImport {
    public static func scanRepository(_ root: URL, framework: ImportFramework) -> [ExistingUIImport.Candidate] {
        let fm = FileManager.default
        let skip: Set<String> = [".git", ".build", ".next", "build", "dist", "node_modules"]
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
            guard isCandidateFile(url, framework: framework),
                  let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            candidates.append(contentsOf: self.candidates(
                inSource: source,
                filePath: url.path,
                repoRoot: root.path,
                preferredName: viewName(for: url, source: source)))
        }
        return candidates.sorted { lhs, rhs in
            if lhs.confidence == rhs.confidence { return lhs.viewName < rhs.viewName }
            return lhs.confidence > rhs.confidence
        }
    }

    public static func candidates(inSource source: String, filePath: String,
                                  repoRoot: String? = nil,
                                  preferredName: String? = nil) -> [ExistingUIImport.Candidate] {
        let parser = WebDOMParser()
        let nodes = parser.parse(source)
        let mapper = WebLayerMapper(filePath: filePath)
        let result = mapper.map(nodes)
        guard result.supported + result.unsupported > 0 else { return [] }

        var warnings = ["Static web import: DOM structure and inline styles are editable; scripts, CSS cascade, and runtime state remain source-owned."]
        if result.unsupported > 0 {
            warnings.append("\(result.unsupported) unsupported web element(s) will import as locked placeholders.")
        }
        if !result.hasAnchors {
            warnings.append("No id/data-vua-anchor/test-id anchors were found; imported layers are editable but source apply remains limited.")
        }

        let total = result.supported + result.unsupported
        let name = preferredName ?? viewName(forPath: filePath, source: source)
        return [
            ExistingUIImport.Candidate(
                viewName: name,
                filePath: filePath,
                repoRoot: repoRoot,
                confidence: total == 0 ? 0 : Double(result.supported) / Double(total),
                supportedElementCount: result.supported,
                unsupportedElementCount: result.unsupported,
                hasAnchors: result.hasAnchors,
                isPreviewOnly: false,
                warnings: warnings)
        ]
    }

    public static func importCandidate(_ candidate: ExistingUIImport.Candidate) -> ExistingUIImport.Imported? {
        let url = URL(fileURLWithPath: candidate.filePath)
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let parser = WebDOMParser()
        let mapper = WebLayerMapper(filePath: candidate.filePath)
        let result = mapper.map(parser.parse(source))
        guard !result.layers.isEmpty else { return nil }
        let view = ParsedView(typeName: candidate.viewName, roots: result.layers, filePath: candidate.filePath)
        // DOM anchors remain on layers for provenance, but the source writer is
        // SwiftUI-specific, so web imports must stay apply-disabled for now.
        return ExistingUIImport.Imported(
            view: view,
            sourceHash: ExistingUIImport.sourceHash(source),
            hasAnchors: false)
    }

    private static func isCandidateFile(_ url: URL, framework: ImportFramework) -> Bool {
        let ext = url.pathExtension.lowercased()
        switch framework {
        case .htmlCSS:
            return ["html", "htm"].contains(ext)
        case .reactNative:
            return ["js", "jsx", "ts", "tsx"].contains(ext)
        case .react, .electron:
            return ["html", "htm", "js", "jsx", "ts", "tsx"].contains(ext)
        default:
            return false
        }
    }

    private static func viewName(for url: URL, source: String) -> String {
        viewName(forPath: url.path, source: source)
    }

    private static func viewName(forPath path: String, source: String) -> String {
        if let component = firstMatch(
            in: source,
            pattern: #"(?:export\s+default\s+function|function|const)\s+([A-Z][A-Za-z0-9_]*)"#
        ) {
            return component
        }
        if let title = firstMatch(in: source, pattern: #"<title[^>]*>([^<]+)</title>"#) {
            return safeTypeName(title)
        }
        return safeTypeName(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
    }

    private static func firstMatch(in source: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = source as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: source, options: [], range: range),
              match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func safeTypeName(_ raw: String) -> String {
        let parts = raw
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let joined = parts.map { part in
            part.prefix(1).uppercased() + part.dropFirst()
        }.joined()
        return joined.isEmpty ? "ImportedWebView" : joined
    }
}

private struct WebLayerResult {
    var layers: [Layer]
    var supported: Int
    var unsupported: Int
    var hasAnchors: Bool
}

private struct WebNode {
    var tag: String
    var attributes: [String: String]
    var children: [WebNode] = []
    var textFragments: [String] = []
}

private struct WebDOMParser {
    func parse(_ source: String) -> [WebNode] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<\s*(/?)\s*([A-Za-z][A-Za-z0-9:._-]*)([^>]*)>"#,
            options: [.dotMatchesLineSeparators]
        ) else { return [] }

        let ns = source as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        var stack = [WebNode(tag: "__root__", attributes: [:])]
        var lastLocation = 0

        for match in regex.matches(in: source, options: [], range: fullRange) {
            if match.range.location > lastLocation {
                appendText(ns.substring(with: NSRange(location: lastLocation, length: match.range.location - lastLocation)), to: &stack)
            }

            let closing = ns.substring(with: match.range(at: 1)) == "/"
            let tag = ns.substring(with: match.range(at: 2))
            let rawAttributes = ns.substring(with: match.range(at: 3))
            if closing {
                close(tag: tag, stack: &stack)
            } else {
                let node = WebNode(tag: tag, attributes: parseAttributes(rawAttributes))
                if isSelfClosing(tag: tag, rawAttributes: rawAttributes) {
                    stack[stack.count - 1].children.append(node)
                } else {
                    stack.append(node)
                }
            }
            lastLocation = match.range.location + match.range.length
        }

        if lastLocation < ns.length {
            appendText(ns.substring(with: NSRange(location: lastLocation, length: ns.length - lastLocation)), to: &stack)
        }
        while stack.count > 1 {
            let node = stack.removeLast()
            stack[stack.count - 1].children.append(node)
        }
        return stack.first?.children ?? []
    }

    private func appendText(_ raw: String, to stack: inout [WebNode]) {
        let collapsed = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return }
        stack[stack.count - 1].textFragments.append(collapsed)
    }

    private func close(tag: String, stack: inout [WebNode]) {
        guard stack.count > 1 else { return }
        let lowerTag = tag.lowercased()
        var index = stack.count - 1
        while index > 0 {
            if stack[index].tag.lowercased() == lowerTag { break }
            index -= 1
        }
        guard index > 0 else { return }
        while stack.count - 1 >= index {
            let node = stack.removeLast()
            stack[stack.count - 1].children.append(node)
        }
    }

    private func parseAttributes(_ raw: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)(?:\s*=\s*("[^"]*"|'[^']*'|\{[^}]*\}|[^\s"'=<>`]+))?"#
        ) else { return [:] }
        let ns = raw as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        var attributes: [String: String] = [:]
        for match in regex.matches(in: raw, options: [], range: fullRange) where match.numberOfRanges > 1 {
            let key = ns.substring(with: match.range(at: 1)).lowercased()
            guard !key.isEmpty else { continue }
            let value: String
            if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
                value = cleanAttributeValue(ns.substring(with: match.range(at: 2)))
            } else {
                value = "true"
            }
            attributes[key] = value
        }
        return attributes
    }

    private func cleanAttributeValue(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value.removeFirst()
            value.removeLast()
        }
        if value.hasPrefix("{"), value.hasSuffix("}") {
            value.removeFirst()
            value.removeLast()
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isSelfClosing(tag: String, rawAttributes: String) -> Bool {
        if rawAttributes.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/") { return true }
        return ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]
            .contains(tag.lowercased())
    }
}

private struct WebLayerMapper {
    let filePath: String

    func map(_ nodes: [WebNode]) -> WebLayerResult {
        var supported = 0
        var unsupported = 0
        var hasAnchors = false
        var layers: [Layer] = []

        for node in nodes {
            let mapped = map(node)
            supported += mapped.supported
            unsupported += mapped.unsupported
            hasAnchors = hasAnchors || mapped.hasAnchors
            layers.append(contentsOf: mapped.layers)
        }

        if layers.count == 1 {
            var root = layers[0]
            ensureRootFrame(&root)
            return WebLayerResult(layers: [root], supported: supported, unsupported: unsupported, hasAnchors: hasAnchors)
        }

        var root = Layer(
            name: "Web Document",
            kind: .container,
            frame: VRect(x: 24, y: 24, width: 640, height: max(240, Double(layers.count) * 64 + 32)),
            children: layers)
        layoutChildren(of: &root)
        return WebLayerResult(layers: [root], supported: supported, unsupported: unsupported, hasAnchors: hasAnchors)
    }

    private func map(_ node: WebNode) -> WebLayerResult {
        let tag = node.tag
        let lower = tag.lowercased()
        var supported = 0
        var unsupported = 0
        var hasAnchors = anchorValue(node.attributes) != nil
        var childLayers: [Layer] = []
        let collapseChildrenIntoText = isButtonLike(lower) && !node.children.contains(where: containsAnchor)

        for child in collapseChildrenIntoText ? [] : node.children {
            let mapped = map(child)
            supported += mapped.supported
            unsupported += mapped.unsupported
            hasAnchors = hasAnchors || mapped.hasAnchors
            childLayers.append(contentsOf: mapped.layers)
        }

        if isIgnoredContainer(lower) {
            return WebLayerResult(layers: childLayers, supported: supported, unsupported: unsupported, hasAnchors: hasAnchors)
        }

        var layer = baseLayer(for: node, childLayers: childLayers)
        if layer.isLocked { unsupported += 1 } else { supported += 1 }
        applyAttributes(node.attributes, text: visibleText(node), to: &layer)
        layoutChildren(of: &layer)
        return WebLayerResult(layers: [layer], supported: supported, unsupported: unsupported, hasAnchors: hasAnchors)
    }

    private func baseLayer(for node: WebNode, childLayers: [Layer]) -> Layer {
        let tag = node.tag
        let lower = tag.lowercased()
        let text = visibleText(node)
        let kind: LayerKind
        let name: String
        var locked = false
        var notes: String?

        switch lower {
        case "main", "section", "article", "header", "footer", "nav", "aside", "div", "form", "ul", "ol", "li":
            kind = .container
            name = label(for: node, fallback: tag)
        case "button", "a":
            kind = .button
            name = text ?? label(for: node, fallback: tag.capitalized)
        case "label", "span", "p", "strong", "em", "small", "h1", "h2", "h3", "h4", "h5", "h6":
            kind = .label
            name = text ?? label(for: node, fallback: tag.capitalized)
        case "textarea":
            kind = .text
            name = text ?? label(for: node, fallback: "Text Area")
        case "select":
            kind = .control
            name = label(for: node, fallback: "Select")
        case "img":
            kind = .image
            name = label(for: node, fallback: "Image")
        case "input":
            let type = node.attributes["type"]?.lowercased() ?? "text"
            switch type {
            case "range":
                kind = .slider
                name = label(for: node, fallback: "Range")
            case "checkbox":
                kind = .toggle
                name = label(for: node, fallback: "Checkbox")
            case "button", "submit", "reset":
                kind = .button
                name = text ?? label(for: node, fallback: "Button")
            default:
                kind = .text
                name = label(for: node, fallback: "Input")
            }
        case "view":
            kind = .container
            name = label(for: node, fallback: "View")
        case "text":
            kind = .label
            name = text ?? label(for: node, fallback: "Text")
        case "pressable", "touchableopacity":
            kind = .button
            name = text ?? label(for: node, fallback: tag)
        case "switch":
            kind = .toggle
            name = label(for: node, fallback: "Switch")
        case "slider":
            kind = .slider
            name = label(for: node, fallback: "Slider")
        case "image":
            kind = .image
            name = label(for: node, fallback: "Image")
        default:
            kind = .custom(typeName: tag)
            name = label(for: node, fallback: tag)
            locked = true
            notes = "\(tag) is preserved as a locked web placeholder because scripts/custom component behaviour cannot be safely edited yet."
        }

        return Layer(
            name: name,
            kind: kind,
            frame: VRect(origin: .zero, size: defaultSize(for: kind, childCount: childLayers.count)),
            text: textForLayer(kind: kind, fallback: text),
            isLocked: locked,
            binding: anchorValue(node.attributes).map { CodeBinding(filePath: filePath, anchorID: $0) },
            notes: notes,
            tags: ["import:web", "tag:\(tag)"],
            children: childLayers)
    }

    private func applyAttributes(_ attributes: [String: String], text: String?, to layer: inout Layer) {
        if let width = numericAttribute("width", in: attributes) { layer.frame.size.width = width }
        if let height = numericAttribute("height", in: attributes) { layer.frame.size.height = height }
        if let style = attributes["style"] {
            apply(style: style, to: &layer)
        }
        if let title = attributes["title"], layer.text == nil { layer.text = title }
        if let placeholder = attributes["placeholder"], layer.text == nil { layer.text = placeholder }
        if let alt = attributes["alt"], layer.text == nil, case .image = layer.kind { layer.name = alt }
        if layer.text == nil { layer.text = textForLayer(kind: layer.kind, fallback: text) }
    }

    private func apply(style raw: String, to layer: inout Layer) {
        let style = parseStyle(raw)
        if let width = number(style["width"]) { layer.frame.size.width = width }
        if let height = number(style["height"]) { layer.frame.size.height = height }
        if let left = number(style["left"]) { layer.frame.origin.x = left }
        if let top = number(style["top"]) { layer.frame.origin.y = top }
        if let background = style["background-color"] ?? style["backgroundcolor"] ?? style["background"],
           let color = color(background) {
            layer.style.backgroundColor = color
        }
        if let foreground = style["color"], let color = color(foreground) {
            layer.style.foregroundColor = color
        }
        if let fontSize = number(style["font-size"] ?? style["fontsize"]) {
            layer.style.fontSize = fontSize
        }
        if let corner = number(style["border-radius"] ?? style["borderradius"]) {
            layer.style.cornerRadius = corner
        }
        if let opacity = number(style["opacity"]) {
            layer.style.opacity = max(0, min(1, opacity))
        }
    }

    private func parseStyle(_ raw: String) -> [String: String] {
        let normalized = raw
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
        let separators = CharacterSet(charactersIn: ";,")
        var pairs: [String: String] = [:]
        for part in normalized.components(separatedBy: separators) {
            let pieces = part.split(separator: ":", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard pieces.count == 2 else { continue }
            pairs[pieces[0].lowercased()] = pieces[1]
        }
        return pairs
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

    private func ensureRootFrame(_ layer: inout Layer) {
        if layer.frame.origin == .zero {
            layer.frame.origin = VPoint(x: 24, y: 24)
        }
        layoutChildren(of: &layer)
    }

    private func isIgnoredContainer(_ lower: String) -> Bool {
        ["__root__", "html", "body", "head", "title", "meta", "link", "style", "script", "noscript", "fragment", "react.fragment"]
            .contains(lower)
    }

    private func isButtonLike(_ lower: String) -> Bool {
        ["button", "a", "pressable", "touchableopacity"].contains(lower)
    }

    private func label(for node: WebNode, fallback: String) -> String {
        anchorValue(node.attributes)
            ?? node.attributes["aria-label"]
            ?? node.attributes["accessibilitylabel"]
            ?? node.attributes["name"]
            ?? node.attributes["classname"]
            ?? node.attributes["class"]
            ?? fallback
    }

    private func visibleText(_ node: WebNode) -> String? {
        var parts = node.textFragments
        parts.append(contentsOf: node.children.compactMap(visibleText))
        let text = parts
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func textForLayer(kind: LayerKind, fallback: String?) -> String? {
        switch kind {
        case .button, .label, .text, .toggle, .control:
            return fallback
        default:
            return nil
        }
    }

    private func anchorValue(_ attributes: [String: String]) -> String? {
        for key in ["data-vua-anchor", "nativeid", "id", "testid", "data-testid", "data-test-id", "accessibilitylabel"] {
            if let value = attributes[key], !value.isEmpty, value != "true" {
                return value
            }
        }
        return nil
    }

    private func containsAnchor(_ node: WebNode) -> Bool {
        if anchorValue(node.attributes) != nil { return true }
        return node.children.contains(where: containsAnchor)
    }

    private func numericAttribute(_ key: String, in attributes: [String: String]) -> Double? {
        guard let value = attributes[key] else { return nil }
        return number(value)
    }

    private func number(_ raw: String?) -> Double? {
        guard var raw else { return nil }
        raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasSuffix("px") { raw.removeLast(2) }
        if raw.hasSuffix("%") { raw.removeLast() }
        return Double(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func color(_ raw: String) -> VColor? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            if value.count == 4 {
                let chars = Array(value.dropFirst())
                return VColor(hex: "#\(chars[0])\(chars[0])\(chars[1])\(chars[1])\(chars[2])\(chars[2])")
            }
            return VColor(hex: value)
        }
        switch value.lowercased() {
        case "black": return .black
        case "white": return .white
        case "transparent": return .clear
        case "red": return VColor(red: 1, green: 0, blue: 0)
        case "green": return VColor(red: 0, green: 0.5, blue: 0)
        case "blue": return VColor(red: 0, green: 0, blue: 1)
        default: return nil
        }
    }

    private func defaultSize(for kind: LayerKind, childCount: Int) -> VSize {
        switch kind {
        case .container, .panel, .group, .background:
            return VSize(width: 320, height: max(120, Double(childCount) * 56 + 32))
        case .button:
            return VSize(width: 120, height: 40)
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
}
