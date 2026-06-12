import Foundation
import SwiftSyntax
import SwiftParser
import VUACore

/// A SwiftUI `View` reconstructed from source into the layer model.
public struct ParsedView: Sendable {
    public var typeName: String
    public var roots: [Layer]
    /// File the view was parsed from (repository-relative or absolute path).
    public var filePath: String

    public init(typeName: String, roots: [Layer], filePath: String) {
        self.typeName = typeName
        self.roots = roots
        self.filePath = filePath
    }
}

/// Parses SwiftUI source into the layer model using SwiftSyntax (no regex).
///
/// Scope: `View` structs whose `body` is a view-builder expression composed of
/// stacks (`VStack`/`HStack`/`ZStack`/`Group`) and common leaves (`Text`,
/// `Button`, `Image`, `Slider`, `Toggle`, `Label`). Recognised modifiers:
/// `frame`, `position`, `offset`, `foregroundStyle`/`foregroundColor`,
/// `background`, `font`, `opacity`, `cornerRadius`, `accessibilityIdentifier`.
/// Explicit `.frame`/`.position` are honoured exactly (round-trips our own
/// generated code); otherwise a stack layout pass assigns frames so imported
/// code is visible and editable.
public struct SwiftUIParser {
    public init() {}

    public func parse(source: String, filePath: String) -> [ParsedView] {
        let tree = Parser.parse(source: source)
        let finder = ViewFinder(viewMode: .sourceAccurate)
        finder.walk(tree)

        var views: [ParsedView] = []
        for decl in finder.viewStructs {
            guard let bodyExpr = Self.bodyExpression(of: decl) else { continue }
            var ctx = ParseContext(filePath: filePath)
            if var root = ctx.parse(bodyExpr) {
                ctx.layout(&root, origin: VPoint(x: 24, y: 24))
                views.append(ParsedView(
                    typeName: decl.name.text,
                    roots: [root],
                    filePath: filePath))
            }
        }
        return views
    }

    /// Extracts the expression returned by a `var body: some View` accessor.
    static func bodyExpression(of decl: StructDeclSyntax) -> ExprSyntax? {
        for member in decl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            for binding in varDecl.bindings {
                guard binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "body" else { continue }
                guard let accessor = binding.accessorBlock else { continue }
                switch accessor.accessors {
                case .getter(let items):
                    return Self.singleExpression(from: items)
                case .accessors(let list):
                    for acc in list where acc.accessorSpecifier.text == "get" {
                        if let body = acc.body { return Self.singleExpression(from: body.statements) }
                    }
                }
            }
        }
        return nil
    }

    /// The view expression from a code block: the `return`ed expression or the
    /// final expression statement.
    static func singleExpression(from items: CodeBlockItemListSyntax) -> ExprSyntax? {
        for item in items {
            if let ret = item.item.as(ReturnStmtSyntax.self) { return ret.expression }
        }
        if let last = items.last?.item.as(ExprSyntax.self) { return last }
        return nil
    }
}

/// Collects every `struct` that conforms to `View`.
final class ViewFinder: SyntaxVisitor {
    private(set) var viewStructs: [StructDeclSyntax] = []

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if let inheritance = node.inheritanceClause {
            let conformsToView = inheritance.inheritedTypes.contains {
                $0.type.as(IdentifierTypeSyntax.self)?.name.text == "View"
            }
            if conformsToView { viewStructs.append(node) }
        }
        return .visitChildren
    }
}
