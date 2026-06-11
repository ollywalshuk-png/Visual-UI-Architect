import Foundation
import SwiftSyntax
import VUACore

/// Carries per-file state while converting SwiftUI syntax into layers.
struct ParseContext {
    let filePath: String

    /// Layers whose origin came from an explicit `.position`/`.offset`.
    private var explicitlyPositioned: Set<UUID> = []
    /// Container axis recorded during parsing for the layout pass.
    private var axisByLayer: [UUID: Axis] = [:]

    enum Axis { case vertical, horizontal, stack }

    init(filePath: String) { self.filePath = filePath }

    // MARK: - Expression → Layer

    mutating func parse(_ expr: ExprSyntax) -> Layer? {
        let (core, modifiers) = Self.peelModifiers(expr)
        guard var layer = parseCore(core) else { return nil }
        apply(modifiers, to: &layer)
        return layer
    }

    /// Splits an expression into its primitive core and the modifier calls
    /// wrapping it (e.g. `Text("x").font(.title).frame(...)`).
    static func peelModifiers(_ expr: ExprSyntax) -> (core: ExprSyntax, modifiers: [FunctionCallExprSyntax]) {
        var modifiers: [FunctionCallExprSyntax] = []
        var current = expr
        while let call = current.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              let base = member.base {
            modifiers.append(call)
            current = base
        }
        return (current, modifiers)
    }

    private mutating func parseCore(_ expr: ExprSyntax) -> Layer? {
        if let call = expr.as(FunctionCallExprSyntax.self),
           let callee = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return parseNamedCall(name: callee.baseName.text, call: call)
        }
        // `Color.white`, `.accentColor`, etc. → background fill.
        if let member = expr.as(MemberAccessExprSyntax.self) {
            var layer = Layer(name: "Color", kind: .background)
            if let color = Self.color(from: ExprSyntax(member)) {
                layer.style.backgroundColor = color
            }
            return layer
        }
        return nil
    }

    private mutating func parseNamedCall(name: String, call: FunctionCallExprSyntax) -> Layer? {
        switch name {
        case "VStack", "HStack", "ZStack", "Group", "NavigationStack", "NavigationView", "List", "Form", "Section":
            var layer = Layer(name: name, kind: .container)
            let children = parseChildren(of: call)
            layer.children = children
            // `Group` with a single child is a transparent wrapper (our codegen
            // emits this) — pass the child through, keeping the wrapper's frame.
            if name == "Group", children.count == 1 {
                return children[0]
            }
            axisByLayer[layer.id] = (name == "HStack") ? .horizontal
                : (name == "ZStack" || name == "Group") ? .stack : .vertical
            if name != "Group" { layer.kind = .container }
            return layer
        case "Text":
            return leaf(.label, name: "Text", text: Self.firstStringArgument(call))
        case "Label":
            return leaf(.label, name: "Label", text: Self.firstStringArgument(call))
        case "Button":
            let text = Self.firstStringArgument(call) ?? Self.firstStringInTrailingClosure(call)
            return leaf(.button, name: "Button", text: text ?? "Button")
        case "Toggle":
            return leaf(.toggle, name: "Toggle", text: Self.firstStringArgument(call) ?? "Toggle")
        case "Image":
            return leaf(.image, name: "Image")
        case "Slider":
            return leaf(.slider, name: "Slider")
        case "TextField":
            return leaf(.text, name: "TextField", text: Self.firstStringArgument(call) ?? "Text Field")
        case "Picker":
            return leaf(.control, name: "Picker", text: Self.firstStringArgument(call) ?? "Picker")
        case "Spacer":
            return leaf(.container, name: "Spacer")
        case "Rectangle":
            return leaf(.shape(.rectangle), name: "Rectangle")
        case "RoundedRectangle":
            return leaf(.shape(.roundedRectangle), name: "Rounded Rectangle")
        case "Circle", "Ellipse":
            return leaf(.shape(.ellipse), name: name == "Circle" ? "Circle" : "Ellipse")
        case "Capsule":
            return leaf(.shape(.capsule), name: "Capsule")
        case "Divider":
            return leaf(.shape(.divider), name: "Divider")
        default:
            // Unknown view type → custom layer preserving its type name.
            return leaf(.custom(typeName: name), name: name)
        }
    }

    private func leaf(_ kind: LayerKind, name: String, text: String? = nil) -> Layer {
        Layer(name: text ?? name, kind: kind,
              frame: VRect(origin: .zero, size: Self.defaultSize(for: kind)),
              text: text)
    }

    private mutating func parseChildren(of call: FunctionCallExprSyntax) -> [Layer] {
        guard let closure = call.trailingClosure else { return [] }
        var layers: [Layer] = []
        for item in closure.statements {
            if let expr = item.item.as(ExprSyntax.self), let layer = parse(expr) {
                layers.append(layer)
            }
        }
        return layers
    }

    // MARK: - Modifier application

    private mutating func apply(_ modifiers: [FunctionCallExprSyntax], to layer: inout Layer) {
        // Frame before position so position can compute origin from size.
        for call in modifiers where modifierName(call) == "frame" {
            applyFrame(call, to: &layer)
        }
        for call in modifiers {
            switch modifierName(call) {
            case "position": applyPosition(call, to: &layer)
            case "offset": applyOffset(call, to: &layer)
            case "foregroundStyle", "foregroundColor":
                if let c = firstColorArgument(call) { layer.style.foregroundColor = c }
            case "background":
                if let c = firstColorArgument(call) { layer.style.backgroundColor = c }
            case "opacity":
                if let d = Self.doubleArgument(call, label: nil) { layer.style.opacity = d }
            case "cornerRadius":
                if let d = Self.doubleArgument(call, label: nil) { layer.style.cornerRadius = d }
            case "font":
                applyFont(call, to: &layer)
            case "accessibilityIdentifier":
                if let id = Self.firstStringArgument(call) {
                    layer.binding = CodeBinding(filePath: filePath, anchorID: id)
                }
            default: break
            }
        }
    }

    private func modifierName(_ call: FunctionCallExprSyntax) -> String {
        call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text ?? ""
    }

    private func applyFrame(_ call: FunctionCallExprSyntax, to layer: inout Layer) {
        if let w = Self.doubleArgument(call, label: "width") { layer.frame.size.width = w }
        if let h = Self.doubleArgument(call, label: "height") { layer.frame.size.height = h }
    }

    private mutating func applyPosition(_ call: FunctionCallExprSyntax, to layer: inout Layer) {
        let x = Self.doubleArgument(call, label: "x")
        let y = Self.doubleArgument(call, label: "y")
        if let x { layer.frame.origin.x = x - layer.frame.width / 2 }
        if let y { layer.frame.origin.y = y - layer.frame.height / 2 }
        if x != nil || y != nil { explicitlyPositioned.insert(layer.id) }
    }

    private mutating func applyOffset(_ call: FunctionCallExprSyntax, to layer: inout Layer) {
        if let x = Self.doubleArgument(call, label: "x") { layer.frame.origin.x += x }
        if let y = Self.doubleArgument(call, label: "y") { layer.frame.origin.y += y }
        explicitlyPositioned.insert(layer.id)
    }

    private func applyFont(_ call: FunctionCallExprSyntax, to layer: inout Layer) {
        // Recognise `.system(size: N)` and a trailing `.weight(.bold)` chain.
        for arg in call.arguments {
            if let inner = arg.expression.as(FunctionCallExprSyntax.self),
               inner.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "system",
               let size = Self.doubleArgument(inner, label: "size") {
                layer.style.fontSize = size
            }
        }
    }

    private func firstColorArgument(_ call: FunctionCallExprSyntax) -> VColor? {
        guard let first = call.arguments.first else { return nil }
        return Self.color(from: first.expression)
    }

    // MARK: - Layout pass

    /// Assigns frames to a layer subtree. Honours explicit positions; otherwise
    /// lays children out by stack semantics.
    mutating func layout(_ layer: inout Layer, origin: VPoint) {
        layer.frame.origin = origin
        guard !layer.children.isEmpty else { return }

        let axis = axisByLayer[layer.id] ?? .stack
        let anyExplicit = layer.children.contains { explicitlyPositioned.contains($0.id) }

        if anyExplicit {
            // Trust authored positions; just recurse for nested containers.
            for i in layer.children.indices {
                var child = layer.children[i]
                layout(&child, origin: child.frame.origin)
                layer.children[i] = child
            }
            if layer.frame.width == 0 || layer.frame.height == 0 {
                layer.frame.size = boundingSize(of: layer.children)
            }
            return
        }

        let spacing = 8.0
        var cursor = 0.0
        for i in layer.children.indices {
            var child = layer.children[i]
            let childOrigin: VPoint
            switch axis {
            case .vertical:   childOrigin = VPoint(x: 0, y: cursor)
            case .horizontal: childOrigin = VPoint(x: cursor, y: 0)
            case .stack:      childOrigin = .zero
            }
            layout(&child, origin: childOrigin)
            layer.children[i] = child
            switch axis {
            case .vertical:   cursor += child.frame.height + spacing
            case .horizontal: cursor += child.frame.width + spacing
            case .stack:      break
            }
        }
        // Container size derived from laid-out children (respect explicit frame).
        let computed = boundingSize(of: layer.children)
        if layer.frame.width == 0 { layer.frame.size.width = computed.width + 16 }
        if layer.frame.height == 0 { layer.frame.size.height = computed.height + 16 }
        // Inset children inside padding.
        for i in layer.children.indices {
            layer.children[i].frame.origin.x += 8
            layer.children[i].frame.origin.y += 8
        }
    }

    private func boundingSize(of layers: [Layer]) -> VSize {
        var maxX = 0.0, maxY = 0.0
        for l in layers {
            maxX = Swift.max(maxX, l.frame.maxX)
            maxY = Swift.max(maxY, l.frame.maxY)
        }
        return VSize(width: maxX, height: maxY)
    }

    // MARK: - Syntax value helpers

    static func firstStringArgument(_ call: FunctionCallExprSyntax) -> String? {
        for arg in call.arguments {
            if let s = stringValue(arg.expression) { return s }
        }
        return nil
    }

    static func firstStringInTrailingClosure(_ call: FunctionCallExprSyntax) -> String? {
        guard let closure = call.trailingClosure else { return nil }
        for item in closure.statements {
            if let inner = item.item.as(ExprSyntax.self)?.as(FunctionCallExprSyntax.self),
               inner.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Text",
               let s = firstStringArgument(inner) {
                return s
            }
        }
        return nil
    }

    static func stringValue(_ expr: ExprSyntax) -> String? {
        guard let lit = expr.as(StringLiteralExprSyntax.self) else { return nil }
        var out = ""
        for segment in lit.segments {
            if let s = segment.as(StringSegmentSyntax.self) { out += s.content.text }
        }
        return out
    }

    static func doubleArgument(_ call: FunctionCallExprSyntax, label: String?) -> Double? {
        for arg in call.arguments {
            if let label {
                if arg.label?.text == label { return doubleValue(arg.expression) }
            } else {
                // First positional (unlabeled) argument.
                if arg.label == nil { return doubleValue(arg.expression) }
            }
        }
        return nil
    }

    static func doubleValue(_ expr: ExprSyntax) -> Double? {
        if let f = expr.as(FloatLiteralExprSyntax.self) { return Double(f.literal.text) }
        if let i = expr.as(IntegerLiteralExprSyntax.self) { return Double(i.literal.text) }
        if let prefix = expr.as(PrefixOperatorExprSyntax.self),
           prefix.operator.text == "-", let v = doubleValue(prefix.expression) {
            return -v
        }
        return nil
    }

    /// Parses a SwiftUI color expression into a domain color.
    static func color(from expr: ExprSyntax) -> VColor? {
        // Color(.sRGB, red: r, green: g, blue: b, opacity: a) or Color(red:green:blue:)
        if let call = expr.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Color" {
            let r = doubleArgument(call, label: "red")
            let g = doubleArgument(call, label: "green")
            let b = doubleArgument(call, label: "blue")
            if let r, let g, let b {
                let a = doubleArgument(call, label: "opacity") ?? 1
                return VColor(red: r, green: g, blue: b, alpha: a)
            }
        }
        // Named colors: `.white`, `Color.black`, etc.
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return namedColor(member.declName.baseName.text)
        }
        return nil
    }

    static func namedColor(_ name: String) -> VColor? {
        switch name {
        case "white": return .white
        case "black": return .black
        case "clear": return .clear
        case "red": return VColor(red: 1, green: 0.23, blue: 0.19)
        case "green": return VColor(red: 0.20, green: 0.78, blue: 0.35)
        case "blue", "accentColor": return VColor(red: 0.04, green: 0.52, blue: 1)
        case "gray", "secondary": return VColor(red: 0.56, green: 0.56, blue: 0.58)
        case "primary": return .white
        default: return nil
        }
    }

    static func defaultSize(for kind: LayerKind) -> VSize {
        switch kind {
        case .button: return VSize(width: 120, height: 44)
        case .label, .text: return VSize(width: 140, height: 22)
        case .slider: return VSize(width: 200, height: 28)
        case .knob: return VSize(width: 64, height: 64)
        case .fader: return VSize(width: 40, height: 160)
        case .meter: return VSize(width: 24, height: 120)
        case .toggle: return VSize(width: 120, height: 32)
        case .image: return VSize(width: 80, height: 80)
        case .panel, .container, .background, .group: return VSize(width: 100, height: 60)
        case .shape, .gradient, .mask: return VSize(width: 100, height: 60)
        case .line: return VSize(width: 120, height: 2)
        case .vectorPath: return VSize(width: 120, height: 80)
        case .polygon: return VSize(width: 80, height: 80)
        case .control, .custom: return VSize(width: 100, height: 60)
        }
    }
}
