import Foundation
import VUACore
import LayerEngine

/// Phase 7 structural checks: invisible/zero-size layers, invalid polygons,
/// fully-masked content, missing asset references, and broken group hierarchy.
public struct StructureValidator: Sendable {
    public init() {}

    public func validate(_ document: Document) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let assetIDs = Set(document.assets.map { $0.id })

        for layer in document.allLayers {
            // Zero / negative size — the layer can never render.
            if layer.frame.width <= 0 || layer.frame.height <= 0 {
                issues.append(ValidationIssue(
                    severity: .warning, category: .structure,
                    message: "\(layer.name) has zero size (\(Int(layer.frame.width))×\(Int(layer.frame.height))).",
                    recommendation: "Give it a non-zero width and height.",
                    layerIDs: [layer.id]))
            }

            // Invisible layer with content — likely an oversight, not an error.
            if !layer.isVisible {
                issues.append(ValidationIssue(
                    severity: .info, category: .structure,
                    message: "\(layer.name) is hidden and won't appear in generated code.",
                    recommendation: nil, layerIDs: [layer.id]))
            }

            // Fully transparent layer that isn't an intentional clear container.
            if layer.style.opacity <= 0.001 {
                issues.append(ValidationIssue(
                    severity: .warning, category: .structure,
                    message: "\(layer.name) is fully transparent (opacity 0).",
                    recommendation: "Raise opacity or hide the layer instead.",
                    layerIDs: [layer.id]))
            }

            // Invalid polygon spec.
            if case .polygon = layer.kind, let poly = layer.polygon, !poly.isValid {
                issues.append(ValidationIssue(
                    severity: .error, category: .structure,
                    message: "\(layer.name) has an invalid polygon (sides \(poly.sides)).",
                    recommendation: "Use at least 3 sides; star ratio must be between 0 and 1.",
                    layerIDs: [layer.id]))
            }

            // Missing asset reference (e.g. a copied group whose asset was deleted).
            if let assetID = layer.assetID, !assetIDs.contains(assetID) {
                issues.append(ValidationIssue(
                    severity: .error, category: .asset,
                    message: "\(layer.name) references a missing asset.",
                    recommendation: "Re-import the asset or clear the reference.",
                    layerIDs: [layer.id]))
            }

            // Empty group — harmless but usually unintended.
            if case .group = layer.kind, layer.children.isEmpty {
                issues.append(ValidationIssue(
                    severity: .info, category: .structure,
                    message: "Group \(layer.name) is empty.",
                    recommendation: "Add children or ungroup it.",
                    layerIDs: [layer.id]))
            }

            // Fully-masked: an inverted shape mask with zero feather hides the
            // whole layer when the mask shape doesn't cover it. Flag invert masks
            // so the user is aware content may be hidden.
            if let mask = layer.mask, mask.invert {
                issues.append(ValidationIssue(
                    severity: .info, category: .structure,
                    message: "\(layer.name) uses an inverted mask — content may be hidden.",
                    recommendation: "Verify the visible region is intended.",
                    layerIDs: [layer.id]))
            }

            for diagnostic in LineTool.validate(layer, canvasSize: document.canvasSize) {
                issues.append(ValidationIssue(
                    severity: diagnostic.code == .unsupportedConnector ? .info : .warning,
                    category: .structure,
                    message: diagnostic.message,
                    recommendation: lineRecommendation(for: diagnostic.code),
                    layerIDs: [layer.id]))
            }
        }
        return issues
    }

    private func lineRecommendation(for code: LineToolDiagnosticCode) -> String {
        switch code {
        case .zeroLength: return "Move the start or end point so the line has length."
        case .invisibleStroke: return "Set a positive stroke width and visible stroke colour."
        case .invalidArrow: return "Lengthen the line or remove one arrowhead."
        case .unsupportedConnector: return "Add explicit connector handles if exact routing matters."
        case .lineOutsideCanvas: return "Move the line back inside the canvas or resize the canvas."
        }
    }
}
