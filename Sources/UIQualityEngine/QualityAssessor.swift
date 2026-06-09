import Foundation
import VUACore

/// A quality finding: not "will it build?" but "is it a good interface?".
public struct QualityIssue: Hashable, Sendable, Identifiable {
    public enum Dimension: String, CaseIterable, Sendable {
        case hierarchy = "Hierarchy"
        case density = "Density"
        case spacing = "Spacing"
        case alignment = "Alignment"
        case contrast = "Contrast"
        case accessibility = "Accessibility"
        case typography = "Typography"
        case noise = "Visual Noise"
    }
    public enum Severity: Int, Comparable, Sendable {
        case note, advisory, problem
        public static func < (l: Severity, r: Severity) -> Bool { l.rawValue < r.rawValue }
    }
    public let id = UUID()
    public var severity: Severity
    public var dimension: Dimension
    public var message: String
    public var recommendation: String
    public var layerIDs: [UUID]

    public init(severity: Severity, dimension: Dimension, message: String,
                recommendation: String, layerIDs: [UUID] = []) {
        self.severity = severity
        self.dimension = dimension
        self.message = message
        self.recommendation = recommendation
        self.layerIDs = layerIDs
    }
}

/// 0–100 scores per quality dimension, plus an overall grade.
public struct QualityScores: Sendable {
    public var designQuality: Int
    public var layoutQuality: Int
    public var visualNoise: Int       // 100 = calm, 0 = chaotic
    public var accessibility: Int
    public var responsiveQuality: Int

    public var overall: Int {
        (designQuality + layoutQuality + visualNoise + accessibility + responsiveQuality) / 5
    }

    public static func grade(_ score: Int) -> String {
        switch score {
        case 90...: return "A"
        case 80..<90: return "B"
        case 65..<80: return "C"
        case 50..<65: return "D"
        default: return "E"
        }
    }
}

public struct QualityReport: Sendable {
    public var issues: [QualityIssue]
    public var scores: QualityScores
    /// The highest-impact fixes, in order.
    public var topRecommendations: [String]
}

/// Heuristic UI-quality assessment over the layer tree: information density,
/// 8-point-grid and spacing consistency, alignment near-misses, WCAG contrast,
/// tap targets, icon-only buttons, text overflow, palette size, and
/// effect-noise. Pure value computation — deterministic and unit-checkable.
public struct QualityAssessor: Sendable {

    public init() {}

    private static let interactive: Set<LayerKind> = [.button, .slider, .knob, .fader, .meter, .toggle, .control]

    public func assess(_ document: Document) -> QualityReport {
        var issues: [QualityIssue] = []
        let all = document.allLayers
        let visible = all.filter(\.isVisible)
        let canvas = document.canvasSize
        let isTouch = document.activeDevice.family == .iPhone || document.activeDevice.family == .iPad

        // --- Density: interactive controls per screen and per area.
        let controls = visible.filter { Self.interactive.contains($0.kind) }
        if controls.count > 30 {
            issues.append(QualityIssue(
                severity: .problem, dimension: .density,
                message: "\(controls.count) interactive controls on one screen — far past comfortable scanning (≈7±2 groups).",
                recommendation: "Split into sections, tabs, or progressive disclosure."))
        } else if controls.count > 18 {
            issues.append(QualityIssue(
                severity: .advisory, dimension: .density,
                message: "\(controls.count) interactive controls on one screen.",
                recommendation: "Group related controls or move secondary actions into menus."))
        }
        let area = canvas.width * canvas.height
        if area > 0, visible.count > 0 {
            let perMegapixel = Double(visible.count) / (area / 1_000_000)
            if perMegapixel > 150 {
                issues.append(QualityIssue(
                    severity: .advisory, dimension: .density,
                    message: "Layer density is very high (\(Int(perMegapixel)) layers per megapixel).",
                    recommendation: "Increase whitespace; remove decoration that doesn't carry information."))
            }
        }

        // --- Spacing: 8-point grid adherence over visible leaf origins.
        let leaves = visible.filter { $0.children.isEmpty }
        if leaves.count >= 4 {
            let offGrid = leaves.filter {
                $0.frame.minX.truncatingRemainder(dividingBy: 4) != 0
                    || $0.frame.minY.truncatingRemainder(dividingBy: 4) != 0
            }
            let ratio = Double(offGrid.count) / Double(leaves.count)
            if ratio > 0.5 {
                issues.append(QualityIssue(
                    severity: .advisory, dimension: .spacing,
                    message: "\(offGrid.count) of \(leaves.count) layers sit off the 4/8-point grid.",
                    recommendation: "Enable snap-to-grid (8 pt) and re-align — consistent rhythm reads as polish.",
                    layerIDs: offGrid.prefix(8).map(\.id)))
            }
        }

        // --- Alignment near-misses: left edges within 1–3 px of each other.
        let edges = leaves.map(\.frame.minX).sorted()
        var nearMisses = 0
        for i in 1..<max(edges.count, 1) where i < edges.count {
            let d = edges[i] - edges[i - 1]
            if d > 0.5 && d < 3.5 { nearMisses += 1 }
        }
        if nearMisses >= 3 {
            issues.append(QualityIssue(
                severity: .advisory, dimension: .alignment,
                message: "\(nearMisses) pairs of layers are almost-but-not-quite left-aligned (1–3 px apart).",
                recommendation: "Use align-left on each group — near-misses read as sloppiness."))
        }

        // --- Contrast: text/label layers against their own or parent background.
        func contrastWalk(_ layers: [Layer], parentBG: VColor?) {
            for layer in layers {
                let bg = layer.style.backgroundColor ?? parentBG
                if layer.kind == .label || layer.kind == .text, let fg = layer.style.foregroundColor, let bg {
                    let ratio = Self.contrastRatio(fg, bg)
                    if ratio < 3 {
                        issues.append(QualityIssue(
                            severity: .problem, dimension: .contrast,
                            message: "“\(layer.name)” text contrast is \(String(format: "%.1f", ratio)):1 — below WCAG AA minimum (4.5:1; 3:1 for large text).",
                            recommendation: "Darken the text or lighten the background.",
                            layerIDs: [layer.id]))
                    } else if ratio < 4.5 {
                        issues.append(QualityIssue(
                            severity: .advisory, dimension: .contrast,
                            message: "“\(layer.name)” text contrast is \(String(format: "%.1f", ratio)):1 — passes only for large text.",
                            recommendation: "Aim for 4.5:1 for body-size text.",
                            layerIDs: [layer.id]))
                    }
                }
                contrastWalk(layer.children, parentBG: bg)
            }
        }
        contrastWalk(document.roots, parentBG: nil)

        // --- Tap targets on touch devices.
        if isTouch {
            for control in controls where min(control.frame.width, control.frame.height) < 44 {
                issues.append(QualityIssue(
                    severity: .problem, dimension: .accessibility,
                    message: "“\(control.name)” is \(Int(control.frame.width))×\(Int(control.frame.height)) pt — below the 44 pt touch minimum.",
                    recommendation: "Grow the control or its tappable padding to at least 44×44 pt.",
                    layerIDs: [control.id]))
            }
        }

        // --- Icon-only buttons without a label.
        for b in visible where b.kind == .button {
            let title = (b.text ?? "").trimmingCharacters(in: .whitespaces)
            if title.isEmpty {
                issues.append(QualityIssue(
                    severity: .advisory, dimension: .accessibility,
                    message: "Button “\(b.name)” has no title — icon-only buttons need an accessibility label.",
                    recommendation: "Set the button text, or keep the name as its screen-reader label.",
                    layerIDs: [b.id]))
            }
        }

        // --- Text overflow: estimated render width vs frame.
        for t in visible where (t.kind == .label || t.kind == .text || t.kind == .button) {
            guard let text = t.text, !text.isEmpty, t.frame.width > 0 else { continue }
            let size = t.style.fontSize ?? 13
            let estimated = Double(text.count) * size * 0.6
            if estimated > t.frame.width * 1.35 {
                issues.append(QualityIssue(
                    severity: .advisory, dimension: .typography,
                    message: "“\(t.name)” text is likely to truncate (≈\(Int(estimated)) pt of text in a \(Int(t.frame.width)) pt frame).",
                    recommendation: "Widen the frame, shorten the copy, or allow wrapping.",
                    layerIDs: [t.id]))
            }
            // Unbreakable runs (long URLs/words) overflow even when wrapping.
            if let longest = text.components(separatedBy: CharacterSet(charactersIn: " \n")).map({ $0.count }).max(),
               Double(longest) * size * 0.6 > t.frame.width * 1.35, longest > 18 {
                issues.append(QualityIssue(
                    severity: .advisory, dimension: .typography,
                    message: "“\(t.name)” contains an unbreakable \(longest)-character run (URL/word) wider than its frame.",
                    recommendation: "Truncate middles of URLs or use a smaller, monospaced style.",
                    layerIDs: [t.id]))
            }
        }

        // --- Palette size: too many distinct colours reads as noise.
        var palette = Set<String>()
        for layer in visible {
            if let c = layer.style.backgroundColor, c.alpha > 0.01 { palette.insert(c.hexString) }
            if let c = layer.style.foregroundColor { palette.insert(c.hexString) }
        }
        if palette.count > 14 {
            issues.append(QualityIssue(
                severity: .advisory, dimension: .noise,
                message: "\(palette.count) distinct colours in one screen.",
                recommendation: "Consolidate to a token palette (Phase 17 design system) — most pro UIs need < 10."))
        }

        // --- Effect noise: shadows/blurs/gradients everywhere.
        let effectCount = visible.reduce(0) {
            $0 + ($1.style.shadow != nil ? 1 : 0) + ($1.style.blurRadius > 0 ? 1 : 0)
                + ($1.style.gradient != nil ? 1 : 0)
        }
        if visible.count >= 8, Double(effectCount) > Double(visible.count) * 0.5 {
            issues.append(QualityIssue(
                severity: .advisory, dimension: .noise,
                message: "\(effectCount) shadow/blur/gradient effects across \(visible.count) layers — effects lose meaning when everything has one.",
                recommendation: "Reserve effects for elevation that matters (modals, primary cards)."))
        }

        // --- Hierarchy: no panel/group structure on a busy screen.
        let containers = visible.filter { $0.kind == .panel || $0.kind == .group || $0.kind == .container }
        if visible.count > 20 && containers.count <= 1 {
            issues.append(QualityIssue(
                severity: .advisory, dimension: .hierarchy,
                message: "\(visible.count) layers with almost no grouping — the eye has no structure to follow.",
                recommendation: "Group related layers into panels/sections with consistent spacing."))
        }

        let scores = Self.score(issues: issues, layerCount: visible.count)
        let top = issues.sorted { $0.severity > $1.severity }.prefix(5).map(\.recommendation)
        return QualityReport(issues: issues, scores: scores, topRecommendations: Array(top))
    }

    // MARK: Scoring

    static func score(issues: [QualityIssue], layerCount: Int) -> QualityScores {
        func dimensionScore(_ dims: Set<QualityIssue.Dimension>) -> Int {
            var s = 100
            for issue in issues where dims.contains(issue.dimension) {
                switch issue.severity {
                case .problem: s -= 18
                case .advisory: s -= 8
                case .note: s -= 3
                }
            }
            return max(0, s)
        }
        return QualityScores(
            designQuality: dimensionScore([.hierarchy, .typography, .contrast]),
            layoutQuality: dimensionScore([.spacing, .alignment, .density]),
            visualNoise: dimensionScore([.noise, .density]),
            accessibility: dimensionScore([.accessibility, .contrast]),
            responsiveQuality: dimensionScore([.density, .typography]))
    }

    /// WCAG contrast ratio between two colours.
    public static func contrastRatio(_ a: VColor, _ b: VColor) -> Double {
        let l1 = max(a.relativeLuminance, b.relativeLuminance)
        let l2 = min(a.relativeLuminance, b.relativeLuminance)
        return (l1 + 0.05) / (l2 + 0.05)
    }
}
