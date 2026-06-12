import Foundation
import SwiftSyntax
import SwiftParser

public enum SwiftUIPropertyWrapperKind: String, Codable, Hashable, Sendable {
    case state
    case binding
    case environment
    case environmentObject
    case observedObject
    case stateObject
    case appStorage
    case sceneStorage
    case focusState
    case query
    case other
}

public struct SwiftUISemanticProperty: Codable, Hashable, Sendable {
    public var name: String
    public var typeAnnotation: String?
    public var initialValue: String?
    public var wrappers: [SwiftUIPropertyWrapperKind]
    public var rawWrappers: [String]
    public var isNavigationPath: Bool
    public var isViewModelLike: Bool
}

public struct SwiftUIForEachSemantic: Codable, Hashable, Sendable {
    public var dataExpression: String
    public var idExpression: String?
    public var itemName: String?
    public var isModelBacked: Bool
}

public struct SwiftUINavigationSemantic: Codable, Hashable, Sendable {
    public var kind: String
    public var pathBinding: String?
    public var destinationType: String?
    public var triggerExpression: String?
}

public struct SwiftUIAsyncSemantic: Codable, Hashable, Sendable {
    public var kind: String
    public var expression: String
}

public enum SwiftUISemanticRelationshipKind: String, Codable, Hashable, Sendable {
    case viewModel
    case environmentObject
    case navigationPath
    case dataSource
    case navigationDestination
    case modalPresentation
    case customView
    case asyncWork
}

public struct SwiftUISemanticRelationship: Codable, Hashable, Sendable {
    public var kind: SwiftUISemanticRelationshipKind
    public var source: String
    public var target: String?
    public var detail: String?

    public init(kind: SwiftUISemanticRelationshipKind, source: String,
                target: String? = nil, detail: String? = nil) {
        self.kind = kind
        self.source = source
        self.target = target
        self.detail = detail
    }
}

public struct SwiftUISemanticView: Codable, Hashable, Sendable {
    public var viewName: String
    public var filePath: String
    public var properties: [SwiftUISemanticProperty]
    public var forEachLoops: [SwiftUIForEachSemantic]
    public var navigation: [SwiftUINavigationSemantic]
    public var asyncHooks: [SwiftUIAsyncSemantic]
    public var conditionalBranchCount: Int
    public var customModifiers: [String]
    public var customViewCalls: [String]
    public var customLayoutTypes: [String]
    public var observableTypes: [String]
    public var relationships: [SwiftUISemanticRelationship]

    public init(viewName: String, filePath: String, properties: [SwiftUISemanticProperty],
                forEachLoops: [SwiftUIForEachSemantic], navigation: [SwiftUINavigationSemantic],
                asyncHooks: [SwiftUIAsyncSemantic], conditionalBranchCount: Int,
                customModifiers: [String], customViewCalls: [String],
                customLayoutTypes: [String], observableTypes: [String],
                relationships: [SwiftUISemanticRelationship] = []) {
        self.viewName = viewName
        self.filePath = filePath
        self.properties = properties
        self.forEachLoops = forEachLoops
        self.navigation = navigation
        self.asyncHooks = asyncHooks
        self.conditionalBranchCount = conditionalBranchCount
        self.customModifiers = customModifiers
        self.customViewCalls = customViewCalls
        self.customLayoutTypes = customLayoutTypes
        self.observableTypes = observableTypes
        self.relationships = relationships
    }

    public var stateLikeProperties: [SwiftUISemanticProperty] {
        properties.filter { property in
            property.wrappers.contains(.state) ||
            property.wrappers.contains(.binding) ||
            property.wrappers.contains(.environmentObject) ||
            property.wrappers.contains(.observedObject) ||
            property.wrappers.contains(.stateObject)
        }
    }

    public var viewModelProperties: [SwiftUISemanticProperty] {
        properties.filter(\.isViewModelLike)
    }

    private enum CodingKeys: String, CodingKey {
        case viewName
        case filePath
        case properties
        case forEachLoops
        case navigation
        case asyncHooks
        case conditionalBranchCount
        case customModifiers
        case customViewCalls
        case customLayoutTypes
        case observableTypes
        case relationships
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        viewName = try container.decode(String.self, forKey: .viewName)
        filePath = try container.decode(String.self, forKey: .filePath)
        properties = try container.decode([SwiftUISemanticProperty].self, forKey: .properties)
        forEachLoops = try container.decode([SwiftUIForEachSemantic].self, forKey: .forEachLoops)
        navigation = try container.decode([SwiftUINavigationSemantic].self, forKey: .navigation)
        asyncHooks = try container.decode([SwiftUIAsyncSemantic].self, forKey: .asyncHooks)
        conditionalBranchCount = try container.decode(Int.self, forKey: .conditionalBranchCount)
        customModifiers = try container.decode([String].self, forKey: .customModifiers)
        customViewCalls = try container.decode([String].self, forKey: .customViewCalls)
        customLayoutTypes = try container.decode([String].self, forKey: .customLayoutTypes)
        observableTypes = try container.decode([String].self, forKey: .observableTypes)
        relationships = try container.decodeIfPresent([SwiftUISemanticRelationship].self, forKey: .relationships) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(viewName, forKey: .viewName)
        try container.encode(filePath, forKey: .filePath)
        try container.encode(properties, forKey: .properties)
        try container.encode(forEachLoops, forKey: .forEachLoops)
        try container.encode(navigation, forKey: .navigation)
        try container.encode(asyncHooks, forKey: .asyncHooks)
        try container.encode(conditionalBranchCount, forKey: .conditionalBranchCount)
        try container.encode(customModifiers, forKey: .customModifiers)
        try container.encode(customViewCalls, forKey: .customViewCalls)
        try container.encode(customLayoutTypes, forKey: .customLayoutTypes)
        try container.encode(observableTypes, forKey: .observableTypes)
        try container.encode(relationships, forKey: .relationships)
    }
}

/// Phase 47: extracts semantic SwiftUI signals that layer parsing deliberately
/// preserves but does not fully model: state, bindings, data loops, navigation,
/// async work, custom modifiers/layouts, and view-model relationships.
public struct SwiftUISemanticAnalyzer {
    public init() {}

    public func analyze(source: String, filePath: String) -> [SwiftUISemanticView] {
        let tree = Parser.parse(source: source)
        let typeScanner = SemanticTypeScanner(viewMode: .sourceAccurate)
        typeScanner.walk(tree)

        return typeScanner.viewStructs.map { decl in
            let visitor = SemanticViewVisitor(
                viewName: decl.name.text,
                filePath: filePath,
                customLayoutTypes: typeScanner.layoutTypes,
                observableTypes: typeScanner.observableTypes,
                knownViewTypes: Set(typeScanner.viewStructs.map { $0.name.text })
            )
            visitor.walk(Syntax(decl))
            return visitor.result()
        }
    }
}

private final class SemanticTypeScanner: SyntaxVisitor {
    private(set) var viewStructs: [StructDeclSyntax] = []
    private(set) var layoutTypes: [String] = []
    private(set) var observableTypes: [String] = []

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if conforms(node.inheritanceClause, to: "View") {
            viewStructs.append(node)
        }
        if conforms(node.inheritanceClause, to: "Layout") {
            layoutTypes.append(node.name.text)
        }
        if hasAttribute("Observable", on: node.attributes) {
            observableTypes.append(node.name.text)
        }
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if hasAttribute("Observable", on: node.attributes) {
            observableTypes.append(node.name.text)
        }
        return .visitChildren
    }

    private func conforms(_ clause: InheritanceClauseSyntax?, to name: String) -> Bool {
        guard let clause else { return false }
        return clause.inheritedTypes.contains { inherited in
            text(inherited.type).split(separator: ".").last.map(String.init) == name
        }
    }

    private func hasAttribute(_ name: String, on attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            guard let attr = element.as(AttributeSyntax.self) else { return false }
            return text(attr.attributeName).split(separator: ".").last.map(String.init) == name
        }
    }
}

private final class SemanticViewVisitor: SyntaxVisitor {
    private let viewName: String
    private let filePath: String
    private let layoutTypes: [String]
    private let observableTypes: [String]
    private let knownViewTypes: Set<String>

    private var properties: [SwiftUISemanticProperty] = []
    private var loops: [SwiftUIForEachSemantic] = []
    private var navigation: [SwiftUINavigationSemantic] = []
    private var asyncHooks: [SwiftUIAsyncSemantic] = []
    private var conditionalBranchCount = 0
    private var customModifiers: Set<String> = []
    private var customViewCalls: Set<String> = []
    private var childViewCalls: Set<String> = []

    init(viewName: String, filePath: String, customLayoutTypes: [String],
         observableTypes: [String], knownViewTypes: Set<String>) {
        self.viewName = viewName
        self.filePath = filePath
        self.layoutTypes = customLayoutTypes
        self.observableTypes = observableTypes
        self.knownViewTypes = knownViewTypes
        super.init(viewMode: .sourceAccurate)
    }

    func result() -> SwiftUISemanticView {
        SwiftUISemanticView(
            viewName: viewName,
            filePath: filePath,
            properties: properties,
            forEachLoops: loops,
            navigation: navigation,
            asyncHooks: asyncHooks,
            conditionalBranchCount: conditionalBranchCount,
            customModifiers: customModifiers.sorted(),
            customViewCalls: customViewCalls.sorted(),
            customLayoutTypes: layoutTypes.sorted(),
            observableTypes: observableTypes.sorted(),
            relationships: buildRelationships())
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let rawWrappers = node.attributes.compactMap { element -> String? in
            guard let attr = element.as(AttributeSyntax.self) else { return nil }
            return text(attr.attributeName).split(separator: ".").last.map(String.init)
        }
        let wrappers = rawWrappers.map(wrapperKind)
        var wrappedPropertySeen = false

        for binding in node.bindings {
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
            guard name != "body" else { continue }
            let typeAnnotation = binding.typeAnnotation.map { text($0.type) }
            let initialValue = binding.initializer.map { text($0.value) }
            let typeText = typeAnnotation ?? ""
            let initText = initialValue ?? ""
            let viewModelLike = rawWrappers.contains(where: { ["StateObject", "ObservedObject", "EnvironmentObject"].contains($0) }) ||
                typeText.contains("ViewModel") || typeText.contains("Store") ||
                name.localizedCaseInsensitiveContains("viewModel")
            wrappedPropertySeen = wrappedPropertySeen || !rawWrappers.isEmpty
            properties.append(SwiftUISemanticProperty(
                name: name,
                typeAnnotation: typeAnnotation,
                initialValue: initialValue,
                wrappers: wrappers,
                rawWrappers: rawWrappers,
                isNavigationPath: typeText.contains("NavigationPath") || initText.contains("NavigationPath"),
                isViewModelLike: viewModelLike))
        }
        return wrappedPropertySeen ? .skipChildren : .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let name = callName(node)
        switch name {
        case "ForEach":
            loops.append(forEachSemantic(node))
        case "NavigationStack", "NavigationSplitView", "NavigationView":
            navigation.append(SwiftUINavigationSemantic(
                kind: name,
                pathBinding: argument(node, label: "path").map(bindingName),
                destinationType: nil,
                triggerExpression: nil))
        case "navigationDestination":
            navigation.append(SwiftUINavigationSemantic(
                kind: name,
                pathBinding: nil,
                destinationType: argument(node, label: "for")?.replacingOccurrences(of: ".self", with: ""),
                triggerExpression: callDetail(node, name: name)))
        case "NavigationLink", "sheet", "fullScreenCover", "popover":
            navigation.append(SwiftUINavigationSemantic(
                kind: name,
                pathBinding: nil,
                destinationType: firstChildViewCall(in: node),
                triggerExpression: callDetail(node, name: name)))
        case "task", "refreshable", "AsyncImage", "Task":
            asyncHooks.append(SwiftUIAsyncSemantic(kind: name, expression: callDetail(node, name: name)))
        default:
            classifyCustomCall(node, name: name)
        }
        return .visitChildren
    }

    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        conditionalBranchCount += 1
        return .visitChildren
    }

    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        conditionalBranchCount += 1
        return .visitChildren
    }

    private func forEachSemantic(_ node: FunctionCallExprSyntax) -> SwiftUIForEachSemantic {
        let data = node.arguments.first.map { text($0.expression) } ?? ""
        let id = argument(node, label: "id")
        let item = trailingClosureParameter(node)
        let isModelBacked = !data.hasPrefix("[") && !data.contains(".constant(")
        return SwiftUIForEachSemantic(dataExpression: data, idExpression: id, itemName: item, isModelBacked: isModelBacked)
    }

    private func classifyCustomCall(_ node: FunctionCallExprSyntax, name: String) {
        guard !name.isEmpty else { return }
        if let first = name.first, first.isUppercase {
            if isChildViewCall(name) {
                childViewCalls.insert(name)
            }
            if !Self.supportedViewCalls.contains(name) && !knownViewTypes.contains(name) {
                customViewCalls.insert(name)
            }
            if text(node.calledExpression).contains("<") && text(node.calledExpression).contains(">") {
                customViewCalls.insert(name)
                childViewCalls.insert(name)
            }
            return
        }
        if node.calledExpression.as(MemberAccessExprSyntax.self) != nil,
           !Self.knownModifiers.contains(name) {
            customModifiers.insert(name)
        }
    }

    private func buildRelationships() -> [SwiftUISemanticRelationship] {
        var relationships: [SwiftUISemanticRelationship] = []
        var seen: Set<SwiftUISemanticRelationship> = []

        func append(_ relationship: SwiftUISemanticRelationship) {
            guard seen.insert(relationship).inserted else { return }
            relationships.append(relationship)
        }

        for property in properties {
            let target = semanticTypeTarget(for: property)
            if property.wrappers.contains(.environmentObject) {
                append(SwiftUISemanticRelationship(
                    kind: .environmentObject,
                    source: property.name,
                    target: target,
                    detail: wrapperDetail(for: property)))
            }
            if property.isViewModelLike {
                append(SwiftUISemanticRelationship(
                    kind: .viewModel,
                    source: property.name,
                    target: target,
                    detail: wrapperDetail(for: property)))
            }
            if property.isNavigationPath {
                append(SwiftUISemanticRelationship(
                    kind: .navigationPath,
                    source: property.name,
                    target: target ?? "NavigationPath",
                    detail: wrapperDetail(for: property)))
            }
        }

        for loop in loops {
            append(SwiftUISemanticRelationship(
                kind: .dataSource,
                source: loop.dataExpression,
                target: loop.itemName,
                detail: dataSourceDetail(for: loop)))
        }

        for route in navigation {
            switch route.kind {
            case "NavigationStack", "NavigationSplitView", "NavigationView":
                if let pathBinding = route.pathBinding {
                    append(SwiftUISemanticRelationship(
                        kind: .navigationPath,
                        source: route.kind,
                        target: pathBinding,
                        detail: "path binding"))
                }
            case "sheet", "fullScreenCover", "popover":
                append(SwiftUISemanticRelationship(
                    kind: .modalPresentation,
                    source: route.kind,
                    target: route.destinationType,
                    detail: compactExpression(route.triggerExpression)))
            default:
                append(SwiftUISemanticRelationship(
                    kind: .navigationDestination,
                    source: route.pathBinding ?? route.kind,
                    target: route.destinationType,
                    detail: compactExpression(route.triggerExpression)))
            }
        }

        for call in childViewCalls.sorted() {
            append(SwiftUISemanticRelationship(
                kind: .customView,
                source: viewName,
                target: call,
                detail: knownViewTypes.contains(call) ? "local view" : "external or unresolved view"))
        }

        for hook in asyncHooks {
            append(SwiftUISemanticRelationship(
                kind: .asyncWork,
                source: hook.kind,
                target: nil,
                detail: compactExpression(hook.expression)))
        }

        return relationships
    }

    private func semanticTypeTarget(for property: SwiftUISemanticProperty) -> String? {
        if let typeAnnotation = property.typeAnnotation {
            return normalizedTypeName(typeAnnotation)
        }
        if let initialValue = property.initialValue {
            return inferredInitializerType(initialValue)
        }
        return nil
    }

    private func wrapperDetail(for property: SwiftUISemanticProperty) -> String? {
        guard !property.rawWrappers.isEmpty else { return nil }
        return property.rawWrappers.map { "@\($0)" }.joined(separator: ", ")
    }

    private func dataSourceDetail(for loop: SwiftUIForEachSemantic) -> String? {
        var details: [String] = [loop.isModelBacked ? "model-backed" : "literal-backed"]
        if let id = loop.idExpression {
            details.append("id: \(id)")
        }
        return details.joined(separator: ", ")
    }

    private func compactExpression(_ expression: String?) -> String? {
        guard let expression else { return nil }
        let compacted = expression
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard compacted.count > 180 else { return compacted }
        return String(compacted.prefix(177)) + "..."
    }

    private func normalizedTypeName(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "!", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func inferredInitializerType(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let paren = trimmed.firstIndex(of: "(") else { return nil }
        let prefix = trimmed[..<paren].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = prefix.split(separator: ".").last else { return nil }
        let candidate = String(last)
        return candidate.first?.isUppercase == true ? candidate : nil
    }

    private func firstChildViewCall(in node: FunctionCallExprSyntax) -> String? {
        guard let closure = node.trailingClosure else { return nil }
        let finder = ChildViewCallFinder(knownViewTypes: knownViewTypes)
        finder.walk(Syntax(closure))
        return finder.firstCall
    }

    private func isChildViewCall(_ name: String) -> Bool {
        guard let first = name.first, first.isUppercase else { return false }
        return !Self.supportedViewCalls.contains(name) || knownViewTypes.contains(name)
    }

    private func callName(_ node: FunctionCallExprSyntax) -> String {
        if let callee = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            return callee.baseName.text
        }
        if let member = node.calledExpression.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return text(node.calledExpression)
    }

    private func argument(_ node: FunctionCallExprSyntax, label: String) -> String? {
        for arg in node.arguments where arg.label?.text == label {
            return text(arg.expression)
        }
        return nil
    }

    private func callDetail(_ node: FunctionCallExprSyntax, name: String) -> String {
        let arguments = node.arguments.map { text($0) }.joined(separator: ", ")
        var detail = arguments.isEmpty ? "\(name)()" : "\(name)(\(arguments))"
        if let trailingClosure = node.trailingClosure {
            detail += " \(text(trailingClosure))"
        }
        return detail
    }

    private func bindingName(_ expression: String) -> String {
        expression.trimmingCharacters(in: CharacterSet(charactersIn: "$ "))
    }

    private func trailingClosureParameter(_ node: FunctionCallExprSyntax) -> String? {
        guard let closure = node.trailingClosure,
              let signatureSyntax = closure.signature else { return nil }
        let signature = text(signatureSyntax)
        guard let first = signature.split(separator: " ").first else { return nil }
        let value = String(first).trimmingCharacters(in: CharacterSet(charactersIn: "{,()"))
        return value.isEmpty || value == "in" ? nil : value
    }

    private func wrapperKind(_ raw: String) -> SwiftUIPropertyWrapperKind {
        switch raw {
        case "State": return .state
        case "Binding": return .binding
        case "Environment": return .environment
        case "EnvironmentObject": return .environmentObject
        case "ObservedObject": return .observedObject
        case "StateObject": return .stateObject
        case "AppStorage": return .appStorage
        case "SceneStorage": return .sceneStorage
        case "FocusState": return .focusState
        case "Query": return .query
        default: return .other
        }
    }

    fileprivate static let supportedViewCalls: Set<String> = [
        "ZStack", "VStack", "HStack", "Group", "NavigationStack", "NavigationSplitView", "NavigationView",
        "TabView", "List", "Form", "Section", "Toolbar", "Menu", "DisclosureGroup", "ViewThatFits", "AnyLayout",
        "GeometryReader", "Canvas", "TimelineView", "ForEach", "Text", "Button", "Toggle", "Image", "Slider",
        "TextField", "SecureField", "Picker", "Stepper", "DatePicker", "Link", "Spacer", "Rectangle",
        "RoundedRectangle", "Circle", "Ellipse", "Capsule", "Divider", "AsyncImage", "NavigationLink"
    ]

    fileprivate static let knownModifiers: Set<String> = [
        "frame", "position", "offset", "foregroundStyle", "foregroundColor", "background", "opacity",
        "cornerRadius", "font", "accessibilityIdentifier", "padding", "toolbar", "navigationTitle",
        "navigationDestination", "sheet", "fullScreenCover", "popover", "task", "refreshable",
        "onAppear", "onDisappear", "animation", "transition", "clipShape", "mask", "overlay",
        "shadow", "blur", "rotationEffect", "scaleEffect", "blendMode", "tag", "disabled"
    ]
}

private final class ChildViewCallFinder: SyntaxVisitor {
    private let knownViewTypes: Set<String>
    private(set) var firstCall: String?

    init(knownViewTypes: Set<String>) {
        self.knownViewTypes = knownViewTypes
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard firstCall == nil else { return .skipChildren }
        let name = callName(node)
        if isChildViewCall(name) {
            firstCall = name
            return .skipChildren
        }
        return .visitChildren
    }

    private func callName(_ node: FunctionCallExprSyntax) -> String {
        if let callee = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            return callee.baseName.text
        }
        if let member = node.calledExpression.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return text(node.calledExpression)
    }

    private func isChildViewCall(_ name: String) -> Bool {
        guard let first = name.first, first.isUppercase else { return false }
        return !SemanticViewVisitor.supportedViewCalls.contains(name) || knownViewTypes.contains(name)
    }
}

private func text(_ syntax: some SyntaxProtocol) -> String {
    syntax.description.trimmingCharacters(in: .whitespacesAndNewlines)
}
