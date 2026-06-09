import Foundation
import SwiftSyntax
import SwiftParser

/// Static analysis of generated SwiftUI source — uses SwiftSyntax, never regex,
/// so we never have to retract a bad export based on a string-match false hit.
public enum GeneratedCodeScanner {

    /// Every `import X` statement at the top level.
    public static func imports(in source: String) -> [String] {
        let tree = Parser.parse(source: source)
        let finder = ImportFinder(viewMode: .sourceAccurate)
        finder.walk(tree)
        return finder.imports
    }

    /// Every `Image("name")` literal reference (excluding `systemName:` calls
    /// and dynamic identifiers we cannot statically prove safe).
    public static func imageReferences(in source: String) -> [String] {
        let tree = Parser.parse(source: source)
        let finder = ImageFinder(viewMode: .sourceAccurate)
        finder.walk(tree)
        return finder.references
    }

    /// True when the source references VUAControls types or imports the module.
    public static func usesControlsLibrary(in source: String) -> Bool {
        if imports(in: source).contains("VUAControls") { return true }
        // Belt-and-braces: a direct type reference also counts.
        let needles = ["KnobView(", "FaderView(", "MeterView(", "ControlView("]
        return needles.contains { source.contains($0) }
    }
}

private final class ImportFinder: SyntaxVisitor {
    var imports: [String] = []
    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        imports.append(node.path.map { $0.name.text }.joined(separator: "."))
        return .skipChildren
    }
}

private final class ImageFinder: SyntaxVisitor {
    var references: [String] = []

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let callee = node.calledExpression.as(DeclReferenceExprSyntax.self),
              callee.baseName.text == "Image" else {
            return .visitChildren
        }
        guard let arg = node.arguments.first else { return .visitChildren }
        // Skip Image(systemName:), Image(nsImage:), Image(decorative:), etc.
        if arg.label?.text != nil { return .visitChildren }
        guard let literal = arg.expression.as(StringLiteralExprSyntax.self) else {
            return .visitChildren
        }
        // Only flat string literals (no interpolation segments).
        var name = ""
        var safe = true
        for segment in literal.segments {
            if let str = segment.as(StringSegmentSyntax.self) {
                name += str.content.text
            } else {
                safe = false
                break
            }
        }
        if safe && !name.isEmpty { references.append(name) }
        return .visitChildren
    }
}
