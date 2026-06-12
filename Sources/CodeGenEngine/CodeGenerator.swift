import Foundation
import VUACore

/// Output of a generation pass.
public struct GeneratedSource: Sendable, Hashable {
    public var fileName: String
    public var contents: String
    public init(fileName: String, contents: String) {
        self.fileName = fileName
        self.contents = contents
    }
}

/// Abstraction over per-target code generators so the app stays target-agnostic.
public protocol CodeGenerator: Sendable {
    var target: CodeGenTarget { get }
    func generate(document: Document) throws -> GeneratedSource
}

public enum CodeGenError: Error, CustomStringConvertible {
    case unsupportedTarget(CodeGenTarget)

    public var description: String {
        switch self {
        case .unsupportedTarget(let t):
            return "Code generation for \(t.displayName) is not implemented yet."
        }
    }
}

/// Routes a document to the generator registered for its target.
public struct CodeGenService: Sendable {
    private let generators: [CodeGenTarget: any CodeGenerator]

    public init(generators: [any CodeGenerator] = [
        SwiftUIGenerator(),
        UIKitGenerator(),
        AppKitGenerator(),
        ReactGenerator(),
        ReactNativeGenerator(),
        HTMLCSSGenerator(),
        ElectronRendererGenerator(),
        FlutterGenerator()
    ]) {
        var map: [CodeGenTarget: any CodeGenerator] = [:]
        for g in generators { map[g.target] = g }
        self.generators = map
    }

    public func generate(_ document: Document) throws -> GeneratedSource {
        guard let generator = generators[document.codeGenTarget] else {
            throw CodeGenError.unsupportedTarget(document.codeGenTarget)
        }
        return try generator.generate(document: document)
    }
}
