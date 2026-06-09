import Foundation
import VUACore

/// A built-in, offline adapter that produces deterministic, rule-based
/// suggestions. It requires no network or external provider, so the AI
/// assistance UI is fully functional out of the box and during testing.
public struct HeuristicAdapter: AgentAdapter {
    public let providerName = "Built-in Heuristics"
    public var isAvailable: Bool { true }

    public init() {}

    public func suggest(_ request: SuggestionRequest) async throws -> [Suggestion] {
        var out: [Suggestion] = []
        let doc = request.document

        if request.kinds.contains(.naming) {
            for layer in doc.allLayers where isDefaultName(layer) {
                out.append(Suggestion(
                    kind: .naming,
                    title: "Rename “\(layer.name)”",
                    detail: "Use a descriptive name based on its role.",
                    proposedChange: .rename(layerID: layer.id, newName: suggestedName(for: layer))))
            }
        }

        if request.kinds.contains(.alignment) {
            // Suggest aligning near-aligned sibling roots.
            let roots = doc.roots.filter { $0.isVisible }
            for i in roots.indices {
                for j in (i + 1)..<roots.count {
                    let a = roots[i], b = roots[j]
                    let dx = abs(a.frame.minX - b.frame.minX)
                    if dx > 0.5 && dx <= 8 {
                        out.append(Suggestion(
                            kind: .alignment,
                            title: "Align \(a.name) and \(b.name) to a shared left edge",
                            detail: "Their left edges differ by \(String(format: "%.1f", dx))pt.",
                            proposedChange: .reframe(
                                layerID: b.id,
                                newFrame: VRect(x: a.frame.minX, y: b.frame.minY,
                                                width: b.frame.width, height: b.frame.height))))
                    }
                }
            }
        }

        return out
    }

    private func isDefaultName(_ layer: Layer) -> Bool {
        layer.name == layer.kind.displayName || layer.name.hasPrefix("Untitled")
    }

    private func suggestedName(for layer: Layer) -> String {
        if let t = layer.text, !t.isEmpty {
            return "\(t.prefix(20)) \(layer.kind.displayName)"
        }
        return "\(layer.kind.displayName) \(String(layer.id.uuidString.prefix(4)))"
    }
}
