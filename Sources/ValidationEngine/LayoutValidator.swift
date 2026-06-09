import Foundation
import VUACore
import LayerEngine

/// Detects layout problems: overlaps, clipping outside parents, off-canvas.
public struct LayoutValidator: Sendable {
    public init() {}

    public func validate(_ document: Document) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let canvas = VRect(origin: .zero, size: document.canvasSize)

        // Off-canvas roots.
        for root in document.roots where root.isVisible {
            let f = root.frame
            if !canvas.intersects(f) {
                issues.append(ValidationIssue(
                    severity: .warning, category: .layout,
                    message: "\(root.name) lies entirely outside the canvas.",
                    recommendation: "Move it within \(Int(canvas.width))×\(Int(canvas.height)).",
                    layerIDs: [root.id]))
            }
        }

        // Children clipping outside their parent bounds.
        for parent in document.allLayers where !parent.children.isEmpty {
            let bounds = VRect(origin: .zero, size: parent.frame.size)
            for child in parent.children where child.isVisible {
                if child.frame.minX < bounds.minX - 0.5 || child.frame.minY < bounds.minY - 0.5 ||
                   child.frame.maxX > bounds.maxX + 0.5 || child.frame.maxY > bounds.maxY + 0.5 {
                    issues.append(ValidationIssue(
                        severity: .warning, category: .clipping,
                        message: "\(child.name) extends beyond \(parent.name).",
                        recommendation: "Resize the child or its parent to avoid clipping.",
                        layerIDs: [child.id, parent.id]))
                }
            }
        }

        // Sibling overlaps among interactive controls (likely unintended).
        for parentLayers in containerGroups(document) {
            let siblings = parentLayers.filter { $0.isVisible }
            for i in siblings.indices {
                for j in (i + 1)..<siblings.count {
                    let a = siblings[i], b = siblings[j]
                    guard isInteractive(a.kind) && isInteractive(b.kind) else { continue }
                    if a.frame.intersects(b.frame) {
                        issues.append(ValidationIssue(
                            severity: .info, category: .overlap,
                            message: "\(a.name) overlaps \(b.name).",
                            recommendation: "Separate overlapping interactive controls.",
                            layerIDs: [a.id, b.id]))
                    }
                }
            }
        }
        return issues
    }

    /// Groups of layers that share a parent (roots, and each container's children).
    private func containerGroups(_ document: Document) -> [[Layer]] {
        var groups: [[Layer]] = [document.roots]
        for layer in document.allLayers where !layer.children.isEmpty {
            groups.append(layer.children)
        }
        return groups
    }

    private func isInteractive(_ kind: LayerKind) -> Bool {
        switch kind {
        case .button, .slider, .knob, .toggle, .control: return true
        default: return false
        }
    }
}

/// Aggregates all validators into a single report. Used by the safe-commit pipeline.
public struct ValidationService: Sendable {
    private let accessibility = AccessibilityValidator()
    private let layout = LayoutValidator()
    private let structure = StructureValidator()
    private let hardening = HardeningValidator()

    public init() {}

    public func validate(_ document: Document, bundleURL: URL? = nil) -> ValidationReport {
        var issues = accessibility.validate(document)
        issues.append(contentsOf: layout.validate(document))
        issues.append(contentsOf: structure.validate(document))
        issues.append(contentsOf: hardening.validate(document, bundleURL: bundleURL))
        issues.sort { $0.severity > $1.severity }
        return ValidationReport(issues: issues)
    }
}
