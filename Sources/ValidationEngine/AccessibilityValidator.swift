import Foundation
import VUACore

/// WCAG contrast math shared by validators and the accessibility panel.
public enum WCAG {
    /// Contrast ratio between two opaque colors. Range 1...21.
    public static func contrastRatio(_ a: VColor, _ b: VColor) -> Double {
        let la = a.relativeLuminance
        let lb = b.relativeLuminance
        let lighter = Swift.max(la, lb)
        let darker = Swift.min(la, lb)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// AA threshold: 4.5 for normal text, 3.0 for large text (>= 24pt, or 19pt bold).
    public static func passesAA(_ ratio: Double, largeText: Bool) -> Bool {
        ratio >= (largeText ? 3.0 : 4.5)
    }

    public static func passesAAA(_ ratio: Double, largeText: Bool) -> Bool {
        ratio >= (largeText ? 4.5 : 7.0)
    }
}

/// Validates accessibility concerns: contrast, touch-target size, missing labels.
public struct AccessibilityValidator: Sendable {
    /// Minimum recommended hit target (points) for touch platforms.
    public var minTouchTarget: Double = 44

    public init() {}

    public func validate(_ document: Document) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let touchPlatform = document.activeDevice.family != .mac

        for layer in document.allLayers where layer.isVisible {
            issues.append(contentsOf: contrastIssues(for: layer))
            if touchPlatform { issues.append(contentsOf: touchTargetIssues(for: layer)) }
            issues.append(contentsOf: labelIssues(for: layer))
        }
        return issues
    }

    private func contrastIssues(for layer: Layer) -> [ValidationIssue] {
        guard isTextBearing(layer.kind),
              let fg = layer.style.foregroundColor,
              let bg = layer.style.backgroundColor else { return [] }
        let ratio = WCAG.contrastRatio(fg, bg)
        let large = (layer.style.fontSize ?? 17) >= 24
        guard !WCAG.passesAA(ratio, largeText: large) else { return [] }
        return [ValidationIssue(
            severity: .error,
            category: .contrast,
            message: "\(layer.name): contrast \(String(format: "%.2f", ratio)):1 fails WCAG AA.",
            recommendation: "Increase contrast to at least \(large ? "3.0" : "4.5"):1.",
            layerIDs: [layer.id])]
    }

    private func touchTargetIssues(for layer: Layer) -> [ValidationIssue] {
        guard isInteractive(layer.kind) else { return [] }
        guard layer.frame.width < minTouchTarget || layer.frame.height < minTouchTarget else { return [] }
        return [ValidationIssue(
            severity: .warning,
            category: .touchTarget,
            message: "\(layer.name): hit target \(Int(layer.frame.width))×\(Int(layer.frame.height)) is below \(Int(minTouchTarget))pt.",
            recommendation: "Enlarge to at least \(Int(minTouchTarget))×\(Int(minTouchTarget))pt.",
            layerIDs: [layer.id])]
    }

    private func labelIssues(for layer: Layer) -> [ValidationIssue] {
        guard isInteractive(layer.kind) else { return [] }
        let hasText = (layer.text?.isEmpty == false)
        guard !hasText else { return [] }
        return [ValidationIssue(
            severity: .warning,
            category: .accessibility,
            message: "\(layer.name): interactive control has no accessible label.",
            recommendation: "Add label text or an accessibilityLabel.",
            layerIDs: [layer.id])]
    }

    private func isTextBearing(_ kind: LayerKind) -> Bool {
        switch kind { case .label, .text, .button: return true; default: return false }
    }

    private func isInteractive(_ kind: LayerKind) -> Bool {
        switch kind {
        case .button, .slider, .knob, .toggle, .control: return true
        default: return false
        }
    }
}
