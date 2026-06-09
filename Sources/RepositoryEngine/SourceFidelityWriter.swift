import Foundation
import SwiftSyntax
import SwiftParser
import VUACore

/// Writes layer geometry changes back into existing SwiftUI source while
/// preserving all surrounding formatting, comments, and unrelated code.
///
/// Nodes are matched by the `.accessibilityIdentifier(_:)` anchor that the
/// code generator emits, so a visual move updates exactly the `.position`
/// (and `.frame`) of the corresponding view — nothing else in the file changes.
public struct SourceFidelityWriter {
    public init() {}

    /// Updates `.position`/`.frame` for the given anchors.
    /// `changes` maps an anchor id to its new (parent-relative) frame.
    public func updatePositions(in source: String, changes: [String: VRect]) throws -> String {
        let tree = Parser.parse(source: source)

        // 1. Map each .position/.frame call (by syntax identity) to new args.
        let collector = ChainCollector(changes: changes, viewMode: .sourceAccurate)
        collector.walk(tree)

        // 2. Rewrite only those calls; everything else (trivia) is untouched.
        let rewriter = GeometryRewriter(targets: collector.targets)
        let newTree = rewriter.visit(tree)
        return newTree.description
    }

    /// Updates `Image(...)` asset names for the given anchors. `changes` maps an
    /// anchor id to the new image/asset name. Converts `Image(systemName:)` to a
    /// named `Image("name")`. All surrounding source is preserved.
    public func updateImageNames(in source: String, changes: [String: String]) throws -> String {
        let tree = Parser.parse(source: source)
        let collector = ImageCollector(changes: changes, viewMode: .sourceAccurate)
        collector.walk(tree)
        let rewriter = ImageRewriter(targets: collector.targets)
        return rewriter.visit(tree).description
    }
}

/// The geometry edit to apply to a single modifier call.
private enum GeometryEdit {
    case position(x: Double, y: Double)
    case frame(width: Double, height: Double)
}

/// Finds `.position`/`.frame` modifier calls belonging to a chain whose
/// `.accessibilityIdentifier` matches a requested anchor.
private final class ChainCollector: SyntaxVisitor {
    let changes: [String: VRect]
    var targets: [SyntaxIdentifier: GeometryEdit] = [:]

    init(changes: [String: VRect], viewMode: SyntaxTreeViewMode) {
        self.changes = changes
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "accessibilityIdentifier",
              let anchor = ParseContext.firstStringArgument(node),
              let rect = changes[anchor] else {
            return .visitChildren
        }
        // Walk down the base chain collecting position/frame calls.
        var current: ExprSyntax? = member.base
        while let expr = current, let call = expr.as(FunctionCallExprSyntax.self),
              let m = call.calledExpression.as(MemberAccessExprSyntax.self) {
            switch m.declName.baseName.text {
            case "position":
                targets[call.id] = .position(x: rect.midX, y: rect.midY)
            case "frame":
                targets[call.id] = .frame(width: rect.width, height: rect.height)
            default:
                break
            }
            current = m.base
        }
        return .visitChildren
    }
}

/// Replaces the argument lists of targeted `.position`/`.frame` calls.
private final class GeometryRewriter: SyntaxRewriter {
    let targets: [SyntaxIdentifier: GeometryEdit]

    init(targets: [SyntaxIdentifier: GeometryEdit]) {
        self.targets = targets
    }

    override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
        let visited = super.visit(node)
        guard let edit = targets[node.id],
              let call = visited.as(FunctionCallExprSyntax.self) else {
            return visited
        }
        switch edit {
        case .position(let x, let y):
            return ExprSyntax(call.with(\.arguments, Self.makeArgs([("x", x), ("y", y)])))
        case .frame(let w, let h):
            // Preserve any non width/height args (e.g. alignment).
            let preserved = call.arguments.filter { $0.label?.text != "width" && $0.label?.text != "height" }
            return ExprSyntax(call.with(\.arguments,
                Self.makeArgs([("width", w), ("height", h)], appending: Array(preserved))))
        }
    }

    /// Builds `label: value, …` argument syntax with conventional spacing.
    static func makeArgs(_ pairs: [(String, Double)],
                         appending extra: [LabeledExprSyntax] = []) -> LabeledExprListSyntax {
        var elements: [LabeledExprSyntax] = []
        for (label, value) in pairs {
            elements.append(LabeledExprSyntax(
                label: .identifier(label),
                colon: .colonToken(trailingTrivia: .space),
                expression: numberExpr(value)))
        }
        elements.append(contentsOf: extra.map { $0.with(\.label, $0.label).with(\.colon, $0.colon) })

        // Re-thread commas: every element but the last gets a trailing comma+space.
        var list: [LabeledExprSyntax] = []
        for (i, var element) in elements.enumerated() {
            if i < elements.count - 1 {
                element = element.with(\.trailingComma, .commaToken(trailingTrivia: .space))
            } else {
                element = element.with(\.trailingComma, nil)
            }
            list.append(element)
        }
        return LabeledExprListSyntax(list)
    }

    static func numberExpr(_ value: Double) -> ExprSyntax {
        if value == value.rounded() {
            return ExprSyntax(IntegerLiteralExprSyntax(literal: .integerLiteral(String(Int(value)))))
        }
        return ExprSyntax(FloatLiteralExprSyntax(literal: .floatLiteral(String(format: "%.2f", value))))
    }
}

/// Finds the `Image(...)` call inside the view anchored by a matching
/// `.accessibilityIdentifier`, recording the new asset name for it.
private final class ImageCollector: SyntaxVisitor {
    let changes: [String: String]
    var targets: [SyntaxIdentifier: String] = [:]

    init(changes: [String: String], viewMode: SyntaxTreeViewMode) {
        self.changes = changes
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "accessibilityIdentifier",
              let anchor = ParseContext.firstStringArgument(node),
              let newName = changes[anchor] else {
            return .visitChildren
        }
        // Descend the base chain to the core view, then find an Image call.
        var current: ExprSyntax? = member.base
        var core: FunctionCallExprSyntax?
        while let expr = current, let call = expr.as(FunctionCallExprSyntax.self) {
            core = call
            current = call.calledExpression.as(MemberAccessExprSyntax.self)?.base
        }
        if let core, let imageCall = Self.findImageCall(in: core) {
            targets[imageCall.id] = newName
        }
        return .visitChildren
    }

    /// Searches a view expression (and any trailing-closure children) for the
    /// first `Image(...)` call.
    static func findImageCall(in call: FunctionCallExprSyntax) -> FunctionCallExprSyntax? {
        if call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Image" {
            return call
        }
        if let closure = call.trailingClosure {
            for item in closure.statements {
                if let expr = item.item.as(ExprSyntax.self) {
                    let (core, _) = ParseContext.peelModifiers(expr)
                    if let inner = core.as(FunctionCallExprSyntax.self),
                       let found = findImageCall(in: inner) {
                        return found
                    }
                }
            }
        }
        return nil
    }
}

/// Replaces the argument of targeted `Image(...)` calls with a named asset.
private final class ImageRewriter: SyntaxRewriter {
    let targets: [SyntaxIdentifier: String]
    init(targets: [SyntaxIdentifier: String]) { self.targets = targets }

    override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
        let visited = super.visit(node)
        guard let newName = targets[node.id],
              let call = visited.as(FunctionCallExprSyntax.self) else {
            return visited
        }
        let stringExpr = StringLiteralExprSyntax(
            openingQuote: .stringQuoteToken(),
            segments: StringLiteralSegmentListSyntax([
                .stringSegment(StringSegmentSyntax(content: .stringSegment(newName)))
            ]),
            closingQuote: .stringQuoteToken())
        let arg = LabeledExprSyntax(expression: ExprSyntax(stringExpr))
        return ExprSyntax(call.with(\.arguments, LabeledExprListSyntax([arg])))
    }
}
