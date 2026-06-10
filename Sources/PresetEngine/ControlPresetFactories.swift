import Foundation
import VUACore

/// Builds 50 control presets per family by crossing the 10 style families with
/// 5 size/parameter variants per kind. Every preset is a real, distinct,
/// code-generatable layer — no placeholders.
enum ControlPresetFactories {

    // MARK: - Variants (5 per kind)

    /// Knob variants: size in points + a typical parameter target.
    private struct KnobVariant { let label: String; let diameter: Double; let param: String; let range: ClosedRange<Double>; let unit: ControlUnit; let defaultValue: Double }
    private static let knobVariants: [KnobVariant] = [
        .init(label: "Cutoff", diameter: 56, param: "cutoff", range: 20...20000, unit: .hertz, defaultValue: 1000),
        .init(label: "Resonance", diameter: 48, param: "resonance", range: 0...100, unit: .percent, defaultValue: 25),
        .init(label: "Drive", diameter: 64, param: "drive", range: 0...24, unit: .decibels, defaultValue: 0),
        .init(label: "Mix", diameter: 40, param: "mix", range: 0...100, unit: .percent, defaultValue: 50),
        .init(label: "Tune", diameter: 72, param: "tune", range: -12...12, unit: .semitones, defaultValue: 0)
    ]

    private struct FaderVariant { let label: String; let width: Double; let height: Double; let param: String; let range: ClosedRange<Double>; let unit: ControlUnit; let defaultValue: Double }
    private static let faderVariants: [FaderVariant] = [
        .init(label: "Channel", width: 28, height: 160, param: "ch_level", range: -60...6, unit: .decibels, defaultValue: 0),
        .init(label: "Master", width: 36, height: 200, param: "master", range: -60...6, unit: .decibels, defaultValue: 0),
        .init(label: "Send A", width: 24, height: 140, param: "send_a", range: -60...0, unit: .decibels, defaultValue: -12),
        .init(label: "Trim", width: 22, height: 110, param: "trim", range: -24...24, unit: .decibels, defaultValue: 0),
        .init(label: "Headroom", width: 30, height: 180, param: "headroom", range: -36...0, unit: .decibels, defaultValue: -6)
    ]

    private struct SliderVariant { let label: String; let width: Double; let param: String; let range: ClosedRange<Double>; let unit: ControlUnit; let defaultValue: Double }
    private static let sliderVariants: [SliderVariant] = [
        .init(label: "Volume", width: 200, param: "volume", range: 0...100, unit: .percent, defaultValue: 75),
        .init(label: "Brightness", width: 220, param: "brightness", range: 0...100, unit: .percent, defaultValue: 65),
        .init(label: "Speed", width: 180, param: "speed", range: 0.25...4, unit: .ratio, defaultValue: 1),
        .init(label: "Threshold", width: 240, param: "threshold", range: -60...0, unit: .decibels, defaultValue: -24),
        .init(label: "Position", width: 160, param: "position", range: 0...1, unit: .generic, defaultValue: 0.5)
    ]

    private struct ButtonVariant { let label: String; let text: String; let width: Double; let height: Double; let weight: LayerStyle.FontWeight }
    private static let buttonVariants: [ButtonVariant] = [
        .init(label: "Default", text: "Continue", width: 120, height: 36, weight: .semibold),
        .init(label: "Wide", text: "Save Changes", width: 200, height: 44, weight: .semibold),
        .init(label: "Compact", text: "OK", width: 72, height: 28, weight: .medium),
        .init(label: "Hero", text: "Get Started", width: 240, height: 52, weight: .bold),
        .init(label: "Icon", text: "+", width: 36, height: 36, weight: .bold)
    ]

    private struct ToggleVariant { let label: String; let text: String; let width: Double; let height: Double }
    private static let toggleVariants: [ToggleVariant] = [
        .init(label: "Notifications", text: "Notifications", width: 220, height: 28),
        .init(label: "Auto Save", text: "Auto Save", width: 200, height: 28),
        .init(label: "Wi-Fi", text: "Wi-Fi", width: 160, height: 28),
        .init(label: "Bypass", text: "Bypass", width: 140, height: 26),
        .init(label: "Solo", text: "Solo", width: 120, height: 26)
    ]

    // MARK: - Public catalog

    static let all: [ControlPreset] = {
        var out: [ControlPreset] = []
        out.reserveCapacity(250)
        for family in StyleFamilies.all {
            for v in knobVariants { out.append(makeKnob(family: family, variant: v)) }
            for v in faderVariants { out.append(makeFader(family: family, variant: v)) }
            for v in sliderVariants { out.append(makeSlider(family: family, variant: v)) }
            for v in buttonVariants { out.append(makeButton(family: family, variant: v)) }
            for v in toggleVariants { out.append(makeToggle(family: family, variant: v)) }
        }
        return out
    }()

    // MARK: - Per-kind constructors

    private static func makeKnob(family: StyleFamily, variant: KnobVariant) -> ControlPreset {
        let name = "\(family.name) \(variant.label) Knob"
        let style = LayerStyle(
            backgroundColor: family.background, foregroundColor: family.accent,
            cornerRadius: variant.diameter / 2,
            borderColor: family.border, borderWidth: family.borderWidth,
            shadow: family.shadow)
        return ControlPreset(
            id: id("knob", family, variant.label),
            kind: .knob, family: family.name, name: name,
            tags: family.tags + ["knob", variant.label.lowercased()],
            size: VSize(width: variant.diameter, height: variant.diameter),
            style: style,
            metadata: ControlMetadata(
                parameterID: variant.param, displayName: variant.label,
                minValue: variant.range.lowerBound, maxValue: variant.range.upperBound,
                defaultValue: variant.defaultValue, unit: variant.unit),
            text: nil)
    }

    private static func makeFader(family: StyleFamily, variant: FaderVariant) -> ControlPreset {
        let name = "\(family.name) \(variant.label) Fader"
        let style = LayerStyle(
            backgroundColor: family.background, foregroundColor: family.accent,
            cornerRadius: min(family.cornerRadius, variant.width / 2),
            borderColor: family.border, borderWidth: family.borderWidth,
            shadow: family.shadow)
        return ControlPreset(
            id: id("fader", family, variant.label),
            kind: .fader, family: family.name, name: name,
            tags: family.tags + ["fader", variant.label.lowercased()],
            size: VSize(width: variant.width, height: variant.height),
            style: style,
            metadata: ControlMetadata(
                parameterID: variant.param, displayName: variant.label,
                minValue: variant.range.lowerBound, maxValue: variant.range.upperBound,
                defaultValue: variant.defaultValue, unit: variant.unit),
            text: nil)
    }

    private static func makeSlider(family: StyleFamily, variant: SliderVariant) -> ControlPreset {
        let name = "\(family.name) \(variant.label) Slider"
        let style = LayerStyle(
            backgroundColor: family.background, foregroundColor: family.accent,
            cornerRadius: family.cornerRadius,
            borderColor: family.border, borderWidth: family.borderWidth)
        return ControlPreset(
            id: id("slider", family, variant.label),
            kind: .slider, family: family.name, name: name,
            tags: family.tags + ["slider", variant.label.lowercased()],
            size: VSize(width: variant.width, height: 28),
            style: style,
            metadata: ControlMetadata(
                parameterID: variant.param, displayName: variant.label,
                minValue: variant.range.lowerBound, maxValue: variant.range.upperBound,
                defaultValue: variant.defaultValue, unit: variant.unit),
            text: nil)
    }

    private static func makeButton(family: StyleFamily, variant: ButtonVariant) -> ControlPreset {
        let name = "\(family.name) \(variant.label) Button"
        let style = LayerStyle(
            backgroundColor: family.background, foregroundColor: family.accent,
            cornerRadius: family.cornerRadius,
            borderColor: family.border, borderWidth: family.borderWidth,
            fontSize: variant.height >= 44 ? 17 : 15,
            fontWeight: variant.weight,
            shadow: family.shadow)
        return ControlPreset(
            id: id("button", family, variant.label),
            kind: .button, family: family.name, name: name,
            tags: family.tags + ["button", variant.label.lowercased()],
            size: VSize(width: variant.width, height: variant.height),
            style: style,
            metadata: nil,
            text: variant.text)
    }

    private static func makeToggle(family: StyleFamily, variant: ToggleVariant) -> ControlPreset {
        let name = "\(family.name) \(variant.label) Switch"
        let style = LayerStyle(
            backgroundColor: family.background, foregroundColor: family.accent,
            cornerRadius: family.cornerRadius,
            borderColor: family.border, borderWidth: family.borderWidth,
            fontSize: 14, fontWeight: .medium)
        return ControlPreset(
            id: id("toggle", family, variant.label),
            kind: .toggle, family: family.name, name: name,
            tags: family.tags + ["toggle", "switch", variant.label.lowercased()],
            size: VSize(width: variant.width, height: variant.height),
            style: style,
            metadata: ControlMetadata(
                parameterID: variant.label.lowercased().replacingOccurrences(of: " ", with: "_"),
                displayName: variant.text,
                minValue: 0, maxValue: 1, defaultValue: 1, unit: .generic,
                isContinuous: false, stepCount: 2),
            text: variant.text)
    }

    private static func id(_ kind: String, _ family: StyleFamily, _ variant: String) -> String {
        let fam = family.name.lowercased().replacingOccurrences(of: " ", with: "_")
        let v = variant.lowercased().replacingOccurrences(of: " ", with: "_")
        return "ctrl.\(kind).\(fam).\(v)"
    }
}

// MARK: - Public library

/// The complete advanced-control preset catalog — 50 per family × 5 families = 250 entries.
public enum ControlPresetLibrary {
    public static var all: [ControlPreset] { ControlPresetFactories.all }

    public static func presets(in kind: ControlPresetKind) -> [ControlPreset] {
        all.filter { $0.kind == kind }
    }

    public static func families(in kind: ControlPresetKind) -> [String] {
        var seen = Set<String>(); var ordered: [String] = []
        for p in presets(in: kind) where !seen.contains(p.family) {
            seen.insert(p.family); ordered.append(p.family)
        }
        return ordered
    }

    public static func search(_ query: String, in kind: ControlPresetKind? = nil) -> [ControlPreset] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pool = kind.map { presets(in: $0) } ?? all
        guard !q.isEmpty else { return pool }
        return pool.filter { preset in
            preset.name.localizedCaseInsensitiveContains(q) ||
            preset.family.localizedCaseInsensitiveContains(q) ||
            preset.tags.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }
}
