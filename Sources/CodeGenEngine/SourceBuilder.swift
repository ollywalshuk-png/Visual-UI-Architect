import Foundation

/// Small indentation-aware string builder for emitting readable source code.
public struct SourceBuilder {
    private var lines: [String] = []
    private var indentLevel = 0
    private let indentUnit: String

    public init(indentUnit: String = "    ") {
        self.indentUnit = indentUnit
    }

    public mutating func line(_ text: String = "") {
        if text.isEmpty {
            lines.append("")
        } else {
            lines.append(String(repeating: indentUnit, count: indentLevel) + text)
        }
    }

    /// Emits `header` then the closure body indented one level deeper.
    public mutating func block(_ header: String, _ body: (inout SourceBuilder) -> Void) {
        line(header)
        indentLevel += 1
        body(&self)
        indentLevel -= 1
    }

    public mutating func indented(_ body: (inout SourceBuilder) -> Void) {
        indentLevel += 1
        body(&self)
        indentLevel -= 1
    }

    public var text: String {
        lines.joined(separator: "\n") + "\n"
    }
}
