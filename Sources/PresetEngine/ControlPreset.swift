import Foundation
import VUACore

/// Which control family a preset belongs to. Mirrors the renderable kinds.
public enum ControlPresetKind: String, CaseIterable, Hashable, Sendable {
    case knob, fader, slider, button, toggle

    public var displayName: String {
        switch self {
        case .knob: return "Knobs"
        case .fader: return "Faders"
        case .slider: return "Sliders"
        case .button: return "Buttons"
        case .toggle: return "Switches"
        }
    }
}

/// A reusable, drop-in control preset: a named style + size + sensible
/// parameter metadata that produces a single layer ready for the canvas and
/// for code generation. Distinct from layout `Preset` (which builds groups).
public struct ControlPreset: Identifiable, Sendable, Hashable {
    public let id: String
    public let kind: ControlPresetKind
    public let family: String
    public let name: String
    public let tags: [String]
    /// Default size in points; the caller may override at insert time.
    public let size: VSize
    /// Default styling (colors, radius, weight…).
    public let style: LayerStyle
    /// Default control metadata (parameter id, range, unit). nil for buttons.
    public let metadata: ControlMetadata?
    /// Initial text for kinds that show a label (button/toggle).
    public let text: String?

    public init(id: String, kind: ControlPresetKind, family: String, name: String,
                tags: [String], size: VSize, style: LayerStyle,
                metadata: ControlMetadata?, text: String?) {
        self.id = id
        self.kind = kind
        self.family = family
        self.name = name
        self.tags = tags
        self.size = size
        self.style = style
        self.metadata = metadata
        self.text = text
    }

    /// Builds the concrete `Layer` for this preset, optionally placed at an
    /// explicit origin (top-left).
    public func makeLayer(at origin: VPoint = .zero) -> Layer {
        Layer(
            name: name,
            kind: layerKind,
            frame: VRect(origin: origin, size: size),
            style: style,
            text: text,
            constraints: [],
            control: metadata,
            role: layerRole,
            tags: tags
        )
    }

    private var layerKind: LayerKind {
        switch kind {
        case .knob: return .knob
        case .fader: return .fader
        case .slider: return .slider
        case .button: return .button
        case .toggle: return .toggle
        }
    }

    private var layerRole: LayerRole? {
        switch kind {
        case .button, .toggle: return .control
        case .knob, .fader, .slider: return .control
        }
    }
}

// MARK: - Style families (named tuples shared across factories)

/// A palette + corner-radius bundle used to colour an entire family.
struct StyleFamily {
    let name: String                // e.g. "Classic Rotary"
    let background: VColor          // primary surface
    let accent: VColor              // foreground / value arc / cap
    let border: VColor?
    let borderWidth: Double
    let cornerRadius: Double
    let shadow: ShadowSpec?
    let tags: [String]              // search hints
}

private extension VColor {
    /// Hex initialiser that traps on bad input — only used for compile-time literals.
    static func h(_ hex: String) -> VColor { VColor(hex: hex) ?? .white }
}

enum StyleFamilies {
    // Ten visual languages, each used across multiple control kinds.
    static let classic = StyleFamily(
        name: "Classic", background: .h("#2C2C2E"), accent: .h("#0A84FF"),
        border: .h("#3A3A3C"), borderWidth: 1, cornerRadius: 8,
        shadow: ShadowSpec(color: VColor(red: 0, green: 0, blue: 0, alpha: 0.4), radius: 4, x: 0, y: 2),
        tags: ["classic", "balanced"])

    static let minimalFlat = StyleFamily(
        name: "Minimal Flat", background: .h("#1C1C1E"), accent: .h("#FFFFFF"),
        border: nil, borderWidth: 0, cornerRadius: 6,
        shadow: nil, tags: ["minimal", "flat", "modern"])

    static let vintage = StyleFamily(
        name: "Vintage", background: .h("#7A5A36"), accent: .h("#FFEEC2"),
        border: .h("#3E2A18"), borderWidth: 1.5, cornerRadius: 10,
        shadow: ShadowSpec(color: VColor(red: 0, green: 0, blue: 0, alpha: 0.5), radius: 5, x: 0, y: 3),
        tags: ["vintage", "warm", "wood"])

    static let modernPro = StyleFamily(
        name: "Modern Pro", background: .h("#23252B"), accent: .h("#5AC8FA"),
        border: .h("#3E4350"), borderWidth: 1, cornerRadius: 12,
        shadow: ShadowSpec(color: VColor(red: 0, green: 0, blue: 0, alpha: 0.45), radius: 6, x: 0, y: 3),
        tags: ["pro", "studio", "blue"])

    static let neon = StyleFamily(
        name: "Neon", background: .h("#0F1117"), accent: .h("#39FF14"),
        border: .h("#39FF14"), borderWidth: 1, cornerRadius: 6,
        shadow: ShadowSpec(color: VColor(red: 0.22, green: 1.0, blue: 0.08, alpha: 0.45), radius: 8, x: 0, y: 0),
        tags: ["neon", "dark", "glow"])

    static let glass = StyleFamily(
        name: "Glass", background: .h("#3A3A3F"), accent: .h("#FFFFFF"),
        border: .h("#FFFFFF"), borderWidth: 0.5, cornerRadius: 14,
        shadow: ShadowSpec(color: VColor(red: 0, green: 0, blue: 0, alpha: 0.25), radius: 8, x: 0, y: 4),
        tags: ["glass", "translucent", "soft"])

    static let pill = StyleFamily(
        name: "Pill", background: .h("#1C1C1E"), accent: .h("#0A84FF"),
        border: nil, borderWidth: 0, cornerRadius: 999,
        shadow: nil, tags: ["pill", "rounded"])

    static let danger = StyleFamily(
        name: "Danger", background: .h("#FF3B30"), accent: .h("#FFFFFF"),
        border: nil, borderWidth: 0, cornerRadius: 8,
        shadow: nil, tags: ["danger", "destructive", "red"])

    static let success = StyleFamily(
        name: "Success", background: .h("#34C759"), accent: .h("#FFFFFF"),
        border: nil, borderWidth: 0, cornerRadius: 8,
        shadow: nil, tags: ["success", "positive", "green"])

    static let mono = StyleFamily(
        name: "Mono", background: .h("#2C2C2E"), accent: .h("#FFFFFF"),
        border: .h("#5A5A5C"), borderWidth: 1, cornerRadius: 4,
        shadow: nil, tags: ["mono", "neutral"])

    /// All ten families in display order.
    static let all: [StyleFamily] = [
        classic, minimalFlat, modernPro, vintage, neon,
        glass, pill, mono, danger, success
    ]
}
