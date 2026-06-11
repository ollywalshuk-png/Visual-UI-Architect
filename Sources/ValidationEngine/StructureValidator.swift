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

            if let transform = layer.assetTransform {
                if layer.assetID == nil && (layer.kind == .image || layer.kind == .background) {
                    issues.append(ValidationIssue(
                        severity: .error, category: .asset,
                        message: "\(layer.name) has transform metadata but no asset.",
                        recommendation: "Attach an asset or clear the transform metadata.",
                        layerIDs: [layer.id]))
                }
                if let crop = transform.crop, !crop.isValidUnitRect {
                    issues.append(ValidationIssue(
                        severity: .error, category: .asset,
                        message: "\(layer.name) crop is outside image bounds.",
                        recommendation: "Keep crop x/y/width/height inside the 0...1 asset bounds.",
                        layerIDs: [layer.id]))
                }
                if transform.blendMode == .normal && layer.style.opacity <= 0.001 {
                    issues.append(ValidationIssue(
                        severity: .warning, category: .structure,
                        message: "\(layer.name) transform is invisible.",
                        recommendation: "Raise opacity or hide the layer intentionally.",
                        layerIDs: [layer.id]))
                }
                let transformedWidth = layer.frame.width * abs(transform.scaleX)
                let transformedHeight = layer.frame.height * abs(transform.scaleY)
                if transformedWidth > document.canvasSize.width * 2 || transformedHeight > document.canvasSize.height * 2 {
                    issues.append(ValidationIssue(
                        severity: .warning, category: .layout,
                        message: "\(layer.name) transformed image is very large.",
                        recommendation: "Reduce scale or confirm this is intentional.",
                        layerIDs: [layer.id]))
                }
                let rotated = layer.style.rotationDegrees.truncatingRemainder(dividingBy: 360) != 0
                if rotated {
                    let expanded = rotatedBounds(width: layer.frame.width * abs(transform.scaleX),
                                                 height: layer.frame.height * abs(transform.scaleY),
                                                 degrees: layer.style.rotationDegrees)
                    let bounds = VRect(origin: .zero, size: document.canvasSize)
                    let rotatedFrame = VRect(
                        x: layer.frame.midX - expanded.width / 2,
                        y: layer.frame.midY - expanded.height / 2,
                        width: expanded.width,
                        height: expanded.height)
                    if !bounds.intersects(rotatedFrame) ||
                        rotatedFrame.origin.x < 0 || rotatedFrame.origin.y < 0 ||
                        rotatedFrame.origin.x + rotatedFrame.width > bounds.width ||
                        rotatedFrame.origin.y + rotatedFrame.height > bounds.height {
                        issues.append(ValidationIssue(
                            severity: .warning, category: .layout,
                            message: "\(layer.name) rotation moves part of the asset off-canvas.",
                            recommendation: "Move, scale, or rotate it back inside the canvas.",
                            layerIDs: [layer.id]))
                    }
                }
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

    private func rotatedBounds(width: Double, height: Double, degrees: Double) -> VSize {
        let radians = degrees * .pi / 180
        let sinA = abs(sin(radians))
        let cosA = abs(cos(radians))
        return VSize(width: width * cosA + height * sinA,
                     height: width * sinA + height * cosA)
    }
}
