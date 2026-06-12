import Foundation
import VUACore

/// Reusable visual control assets. Unlike Phase 16 presets, these model the
/// asset role/function/behaviour expectations explicitly so imported or
/// generated controls can be treated as functional UI building blocks.
public enum ControlAssetCategory: String, CaseIterable, Hashable, Sendable {
    case knob, fader, slider, button, toggle, meter, display, panel

    public var displayName: String {
        switch self {
        case .knob: return "Knobs"
        case .fader: return "Faders"
        case .slider: return "Sliders"
        case .button: return "Buttons"
        case .toggle: return "Switches"
        case .meter: return "Meters"
        case .display: return "Displays"
        case .panel: return "Panels"
        }
    }

    public var defaultRole: AssetRole {
        switch self {
        case .knob: return .knobCap
        case .fader: return .faderCap
        case .slider: return .faderCap
        case .button: return .button
        case .toggle: return .toggleSwitch
        case .meter: return .meterLED
        case .display: return .decoration
        case .panel: return .backplate
        }
    }

    public var defaultFunction: AssetFunction {
        switch self {
        case .knob: return .rotaryControl
        case .fader, .slider: return .linearControl
        case .button: return .pressControl
        case .toggle: return .toggleControl
        case .meter, .display, .panel: return .displayOnly
        }
    }

    public var layerKind: LayerKind {
        switch self {
        case .knob: return .knob
        case .fader: return .fader
        case .slider: return .slider
        case .button: return .button
        case .toggle: return .toggle
        case .meter: return .meter
        case .display: return .text
        case .panel: return .panel
        }
    }
}

public enum ControlBehaviourHint: String, CaseIterable, Hashable, Sendable {
    case rotaryKnob
    case endlessEncoder
    case steppedKnob
    case bipolarKnob
    case verticalFader
    case horizontalSlider
    case buttonPress
    case toggleSwitch
    case meterReadout
    case valueDisplay

    public var displayName: String {
        switch self {
        case .rotaryKnob: return "Rotary knob"
        case .endlessEncoder: return "Endless encoder"
        case .steppedKnob: return "Stepped knob"
        case .bipolarKnob: return "Bipolar knob"
        case .verticalFader: return "Vertical fader"
        case .horizontalSlider: return "Horizontal slider"
        case .buttonPress: return "Button press"
        case .toggleSwitch: return "Toggle switch"
        case .meterReadout: return "Meter readout"
        case .valueDisplay: return "Value display"
        }
    }
}

public struct ControlVisualStyle: Hashable, Sendable {
    public var family: String
    public var surface: VColor
    public var accent: VColor
    public var border: VColor?
    public var cornerRadius: Double
    public var material: String

    public init(family: String, surface: VColor, accent: VColor, border: VColor?,
                cornerRadius: Double, material: String) {
        self.family = family
        self.surface = surface
        self.accent = accent
        self.border = border
        self.cornerRadius = cornerRadius
        self.material = material
    }
}

public struct ControlAsset: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let category: ControlAssetCategory
    public let role: AssetRole
    public let function: AssetFunction
    public let defaultSize: VSize
    public let visualStyle: ControlVisualStyle
    public let behaviour: ControlBehaviourHint
    public let valueRange: ClosedRange<Double>?
    public let defaultValue: Double?
    public let unit: ControlUnit
    public let accessibilityLabelTemplate: String
    public let tags: [String]

    public init(id: String, name: String, category: ControlAssetCategory,
                role: AssetRole, function: AssetFunction, defaultSize: VSize,
                visualStyle: ControlVisualStyle, behaviour: ControlBehaviourHint,
                valueRange: ClosedRange<Double>?, defaultValue: Double?,
                unit: ControlUnit, accessibilityLabelTemplate: String,
                tags: [String]) {
        self.id = id
        self.name = name
        self.category = category
        self.role = role
        self.function = function
        self.defaultSize = defaultSize
        self.visualStyle = visualStyle
        self.behaviour = behaviour
        self.valueRange = valueRange
        self.defaultValue = defaultValue
        self.unit = unit
        self.accessibilityLabelTemplate = accessibilityLabelTemplate
        self.tags = tags
    }

    public var metadata: AssetMetadata {
        var binding = AssetControlBinding(
            parameterID: parameterID,
            displayName: name,
            minValue: valueRange?.lowerBound,
            maxValue: valueRange?.upperBound,
            defaultValue: defaultValue,
            unit: unit,
            automationEnabled: ![.button, .display, .panel].contains(category),
            isContinuous: ![.button, .toggle, .display, .panel].contains(category),
            stepCount: (category == .button || category == .toggle) ? 2 : nil)

        if behaviour == .steppedKnob {
            binding.isContinuous = false
            binding.stepCount = 12
        }

        return AssetMetadata(
            role: role,
            function: function,
            interaction: interaction,
            rotation: rotation,
            drag: drag,
            binding: binding)
    }

    public func makeLayer(at origin: VPoint = .zero) -> Layer {
        var control = metadata.binding.toControlMetadata()
        control?.behaviourType = controlBehaviourType
        control?.interactionMode = interactionMode
        control?.responseCurve = responseCurve
        control?.rotationStartDegrees = rotation?.minDegrees
        control?.rotationEndDegrees = rotation?.maxDegrees
        control?.automationEnabled = metadata.binding.automationEnabled
        control?.demoMode = demoMode
        control?.displayMode = displayMode
        control?.demoAnimationEnabled = demoAnimationEnabled
        control?.statusText = statusText
        return Layer(
            name: name,
            kind: category.layerKind,
            frame: VRect(origin: origin, size: defaultSize),
            style: layerStyle,
            text: layerText,
            constraints: [],
            control: control,
            role: .control,
            notes: "Control asset: \(behaviour.displayName). Accessibility: \(accessibilityLabelTemplate).",
            tags: tags + [category.rawValue, role.rawValue, function.rawValue])
    }

    private var layerStyle: LayerStyle {
        LayerStyle(
            backgroundColor: visualStyle.surface,
            foregroundColor: visualStyle.accent,
            cornerRadius: resolvedCornerRadius,
            borderColor: visualStyle.border,
            borderWidth: visualStyle.border == nil ? 0 : 1,
            fontSize: category == .button || category == .toggle ? 14 : nil,
            fontWeight: category == .button ? .semibold : .medium,
            shadow: visualStyle.material.contains("glass") || visualStyle.material.contains("metal")
                ? ShadowSpec(color: VColor(red: 0, green: 0, blue: 0, alpha: 0.32), radius: 5, x: 0, y: 2)
                : nil)
    }

    private var resolvedCornerRadius: Double {
        switch category {
        case .knob: return min(defaultSize.width, defaultSize.height) / 2
        case .toggle: return defaultSize.height / 2
        case .fader: return min(8, defaultSize.width / 2)
        case .slider, .meter, .display: return min(visualStyle.cornerRadius, defaultSize.height / 2)
        case .button: return visualStyle.cornerRadius
        case .panel: return visualStyle.cornerRadius
        }
    }

    private var layerText: String? {
        switch category {
        case .button, .toggle, .display: return name.replacingOccurrences(of: " Button", with: "")
            .replacingOccurrences(of: " Switch", with: "")
        default: return nil
        }
    }

    private var parameterID: String {
        id.replacingOccurrences(of: "asset.", with: "")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }

    private var interaction: InteractionType {
        switch behaviour {
        case .rotaryKnob, .bipolarKnob, .steppedKnob: return .rotaryRelative
        case .endlessEncoder: return .circularDrag
        case .verticalFader: return .verticalDrag
        case .horizontalSlider: return .horizontalDrag
        case .buttonPress, .toggleSwitch: return .tap
        case .meterReadout, .valueDisplay: return .none
        }
    }

    private var controlBehaviourType: String {
        switch behaviour {
        case .rotaryKnob: return "rotaryKnob"
        case .endlessEncoder: return "endlessEncoder"
        case .steppedKnob: return "steppedKnob"
        case .bipolarKnob: return "bipolarKnob"
        case .verticalFader: return "verticalFader"
        case .horizontalSlider: return "horizontalSlider"
        case .buttonPress: return "buttonPress"
        case .toggleSwitch: return "toggleSwitch"
        case .meterReadout: return "meterReadout"
        case .valueDisplay: return "valueDisplay"
        }
    }

    private var interactionMode: String {
        switch behaviour {
        case .rotaryKnob: return "verticalDragRotary"
        case .endlessEncoder: return "relative"
        case .steppedKnob: return "steppedSelector"
        case .bipolarKnob: return "bipolarCenter"
        case .verticalFader, .horizontalSlider: return "linearDrag"
        case .buttonPress: return "press"
        case .toggleSwitch: return "toggle"
        case .meterReadout, .valueDisplay: return "readOnly"
        }
    }

    private var demoMode: String? {
        switch category {
        case .meter:
            if name.localizedCaseInsensitiveContains("stereo") { return "stereo" }
            if name.localizedCaseInsensitiveContains("VU") { return "vu" }
            if name.localizedCaseInsensitiveContains("RMS") { return "rms" }
            return "peak"
        case .display:
            if name.localizedCaseInsensitiveContains("spectrum") { return "rms" }
            if name.localizedCaseInsensitiveContains("preset") { return nil }
            return "progress"
        default:
            return nil
        }
    }

    private var displayMode: String? {
        guard category == .display else { return nil }
        if name.localizedCaseInsensitiveContains("spectrum") { return "spectrumMock" }
        if name.localizedCaseInsensitiveContains("preset") { return "presetName" }
        if name.localizedCaseInsensitiveContains("status") { return "statusText" }
        return "valueReadout"
    }

    private var demoAnimationEnabled: Bool? {
        switch category {
        case .meter, .display: return true
        default: return nil
        }
    }

    private var statusText: String? {
        guard category == .display else { return nil }
        if name.localizedCaseInsensitiveContains("preset") { return "Init Preset" }
        if name.localizedCaseInsensitiveContains("status") { return "Ready" }
        return nil
    }

    private var responseCurve: String {
        behaviour == .bipolarKnob ? "bipolar" : "linear"
    }

    private var rotation: RotationBehaviour? {
        switch behaviour {
        case .rotaryKnob, .steppedKnob: return RotationBehaviour()
        case .bipolarKnob: return RotationBehaviour(minDegrees: -135, maxDegrees: 135, zeroDegrees: 0)
        case .endlessEncoder: return RotationBehaviour(minDegrees: -180, maxDegrees: 180, zeroDegrees: 0)
        default: return nil
        }
    }

    private var drag: DragBehaviour? {
        switch behaviour {
        case .verticalFader: return DragBehaviour(axis: .vertical, pixelsPerFullSweep: max(120, defaultSize.height))
        case .horizontalSlider: return DragBehaviour(axis: .horizontal, pixelsPerFullSweep: max(120, defaultSize.width))
        default: return nil
        }
    }
}

public enum ControlAssetLibrary {
    public static let all: [ControlAsset] = {
        var out: [ControlAsset] = []
        for category in ControlAssetCategory.allCases {
            for spec in specs(for: category) {
                out.append(makeAsset(category: category, spec: spec))
            }
        }
        return out
    }()

    public static func assets(in category: ControlAssetCategory) -> [ControlAsset] {
        all.filter { $0.category == category }
    }

    public static func search(_ query: String, in category: ControlAssetCategory? = nil) -> [ControlAsset] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pool = category.map { assets(in: $0) } ?? all
        guard !q.isEmpty else { return pool }
        return pool.filter { asset in
            asset.name.localizedCaseInsensitiveContains(q) ||
            asset.visualStyle.family.localizedCaseInsensitiveContains(q) ||
            asset.tags.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    private struct Spec {
        let name: String
        let style: ControlVisualStyle
        let size: VSize
        let behaviour: ControlBehaviourHint
        let range: ClosedRange<Double>?
        let defaultValue: Double?
        let unit: ControlUnit
        let tags: [String]
    }

    private static func specs(for category: ControlAssetCategory) -> [Spec] {
        switch category {
        case .knob: return named(knobs, category: category)
        case .fader: return named(faders, category: category)
        case .slider: return named(sliders, category: category)
        case .button: return named(buttons, category: category)
        case .toggle: return named(toggles, category: category)
        case .meter: return named(meters, category: category)
        case .display: return named(displays, category: category)
        case .panel: return named(panels, category: category)
        }
    }

    private static func named(_ names: [String], category: ControlAssetCategory) -> [Spec] {
        names.enumerated().map { index, name in
            let style = styles[index % styles.count]
            return Spec(
                name: name,
                style: style,
                size: size(for: category, index: index),
                behaviour: behaviour(for: category, name: name, index: index),
                range: range(for: category, name: name),
                defaultValue: defaultValue(for: category, name: name),
                unit: unit(for: category, name: name),
                tags: tags(for: category, name: name, style: style))
        }
    }

    private static func makeAsset(category: ControlAssetCategory, spec: Spec) -> ControlAsset {
        ControlAsset(
            id: "asset.\(category.rawValue).\(slug(spec.name))",
            name: spec.name.capitalizedWords,
            category: category,
            role: category.defaultRole,
            function: category.defaultFunction,
            defaultSize: spec.size,
            visualStyle: spec.style,
            behaviour: spec.behaviour,
            valueRange: spec.range,
            defaultValue: spec.defaultValue,
            unit: spec.unit,
            accessibilityLabelTemplate: "\(spec.name.capitalizedWords) value",
            tags: spec.tags)
    }

    private static let styles: [ControlVisualStyle] = [
        .init(family: "Classic", surface: .h("#2C2C2E"), accent: .h("#0A84FF"), border: .h("#545458"), cornerRadius: 8, material: "painted metal"),
        .init(family: "Modern Flat", surface: .h("#1C1C1E"), accent: .h("#FFFFFF"), border: nil, cornerRadius: 6, material: "flat"),
        .init(family: "Vintage", surface: .h("#7A5A36"), accent: .h("#FFEEC2"), border: .h("#3E2A18"), cornerRadius: 10, material: "vintage bakelite"),
        .init(family: "Studio Blue", surface: .h("#20242C"), accent: .h("#5AC8FA"), border: .h("#46515F"), cornerRadius: 10, material: "soft-touch"),
        .init(family: "Neon", surface: .h("#0F1117"), accent: .h("#39FF14"), border: .h("#39FF14"), cornerRadius: 6, material: "emissive"),
        .init(family: "Glass", surface: .h("#3A3A3F"), accent: .h("#FFFFFF"), border: .h("#FFFFFF"), cornerRadius: 14, material: "glass"),
        .init(family: "Silver", surface: .h("#B8BDC7"), accent: .h("#1C1C1E"), border: .h("#6E7480"), cornerRadius: 9, material: "brushed metal"),
        .init(family: "Dark Pro", surface: .h("#111318"), accent: .h("#FF9F0A"), border: .h("#323741"), cornerRadius: 7, material: "matte"),
        .init(family: "Soft Pad", surface: .h("#34363D"), accent: .h("#FF375F"), border: nil, cornerRadius: 12, material: "rubber"),
        .init(family: "Utility", surface: .h("#E5E5EA"), accent: .h("#007AFF"), border: .h("#AEAEB2"), cornerRadius: 5, material: "system")
    ]

    private static let proFamilies = ["logic-inspired", "ableton-inspired", "ssl-inspired", "neve-inspired", "api-inspired", "moog-inspired", "nord-inspired", "roland-inspired", "elektron-inspired", "apple-inspired", "glass-inspired"]

    private static let knobs = expanded(["classic rotary", "modern flat", "vintage pointer", "moog-style", "minimal dot", "encoder ring"], count: 60, suffix: "knob")
    private static let faders = expanded(["channel strip", "master", "send", "trim", "slim studio", "dark mixer"], count: 60, suffix: "fader")
    private static let sliders = ["horizontal value slider", "range slider", "bipolar slider", "segmented slider", "compact slider", "settings slider", "brightness slider", "volume slider", "scrub slider", "timeline slider", "blue pro slider", "minimal slider", "chunky slider", "glass slider", "dark slider", "iOS-style slider", "macOS-style slider", "parameter slider", "stepped slider", "fine-control slider"]
    private static let buttons = ["push button", "icon button", "wide button", "hero button", "toolbar button", "soft button", "glass button", "dark pro button", "danger button", "success button", "transport button", "segmented button", "square pad", "round pad", "toggle button", "preset button", "menu button", "bypass button", "macro button", "compact button"]
    private static let toggles = expanded(["bypass", "solo", "mute", "power"], count: 40, suffix: "switch")
    private static let meters = expanded(["vertical", "horizontal", "stereo", "peak"], count: 40, suffix: "meter")
    private static let displays = expanded(["OLED readout", "LCD value", "spectrum", "preset"], count: 30, suffix: "display")
    private static let panels = expanded(["rack backplate", "device body", "glass surface", "mixer strip"], count: 30, suffix: "panel")

    private static func size(for category: ControlAssetCategory, index: Int) -> VSize {
        switch category {
        case .knob: return VSize(width: [40, 48, 56, 64, 72][index % 5], height: [40, 48, 56, 64, 72][index % 5])
        case .fader: return VSize(width: [24, 28, 32, 36, 42][index % 5], height: [128, 150, 170, 190, 220][index % 5])
        case .slider: return VSize(width: [150, 180, 210, 240, 280][index % 5], height: [24, 26, 28, 30, 32][index % 5])
        case .button: return VSize(width: [72, 96, 128, 180, 220][index % 5], height: [28, 32, 36, 44, 52][index % 5])
        case .toggle: return VSize(width: [96, 116, 140, 170, 200][index % 5], height: [26, 28, 30, 32, 36][index % 5])
        case .meter: return index % 3 == 1 ? VSize(width: 180, height: 24) : VSize(width: [20, 24, 28, 36, 44][index % 5], height: [110, 140, 170, 200, 230][index % 5])
        case .display: return VSize(width: [120, 150, 180, 220, 260][index % 5], height: [36, 44, 54, 64, 80][index % 5])
        case .panel: return VSize(width: [280, 360, 440, 520, 640][index % 5], height: [160, 220, 280, 340, 420][index % 5])
        }
    }

    private static func behaviour(for category: ControlAssetCategory, name: String, index: Int) -> ControlBehaviourHint {
        switch category {
        case .knob:
            if name.contains("encoder") { return .endlessEncoder }
            if name.contains("stepped") || name.contains("selector") { return .steppedKnob }
            if name.contains("bipolar") || name.contains("pan") { return .bipolarKnob }
            return .rotaryKnob
        case .fader: return .verticalFader
        case .slider: return .horizontalSlider
        case .button: return .buttonPress
        case .toggle: return .toggleSwitch
        case .meter: return .meterReadout
        case .display: return .valueDisplay
        case .panel: return .meterReadout
        }
    }

    private static func range(for category: ControlAssetCategory, name: String) -> ClosedRange<Double>? {
        switch category {
        case .button: return 0...1
        case .toggle: return 0...1
        case .meter, .display: return name.contains("CPU") || name.contains("progress") ? 0...100 : -60...6
        case .panel: return nil
        default:
            if name.contains("pan") || name.contains("bipolar") { return -100...100 }
            if name.contains("fine") || name.contains("tune") { return -12...12 }
            if name.contains("filter") { return 20...20000 }
            return 0...100
        }
    }

    private static func defaultValue(for category: ControlAssetCategory, name: String) -> Double? {
        switch category {
        case .button, .toggle: return category == .toggle ? 1 : 0
        case .meter, .display: return name.contains("CPU") || name.contains("progress") ? 50 : -18
        case .panel: return nil
        default:
            if name.contains("pan") || name.contains("bipolar") || name.contains("tune") { return 0 }
            if name.contains("filter") { return 1000 }
            return 50
        }
    }

    private static func unit(for category: ControlAssetCategory, name: String) -> ControlUnit {
        if name.contains("meter") || name.contains("level") || name.contains("gain") || name.contains("fader") { return .decibels }
        if name.contains("filter") { return .hertz }
        if name.contains("tune") { return .semitones }
        if name.contains("CPU") || name.contains("progress") || name.contains("mix") { return .percent }
        return [.button, .toggle, .display, .panel].contains(category) ? .generic : .percent
    }

    private static func tags(for category: ControlAssetCategory, name: String, style: ControlVisualStyle) -> [String] {
        var tags = [category.rawValue, category.displayName.lowercased(), style.family.lowercased(), style.material]
        tags.append(contentsOf: name.lowercased().split(separator: " ").map(String.init))
        return Array(Set(tags)).sorted()
    }

    private static func slug(_ value: String) -> String {
        value.lowercased().map { ch in
            ch.isLetter || ch.isNumber ? String(ch) : "-"
        }.joined().split(separator: "-").joined(separator: "-")
    }

    private static func expanded(_ bases: [String], count: Int, suffix: String) -> [String] {
        (0..<count).map { index in
            let family = proFamilies[index % proFamilies.count]
            let base = bases[index % bases.count]
            let variant = (index / bases.count) + 1
            return "\(family) \(base) \(suffix) \(variant)"
        }
    }
}

private extension String {
    var capitalizedWords: String {
        split(separator: " ").map { word in
            guard let first = word.first else { return "" }
            return first.uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
}

private extension VColor {
    static func h(_ hex: String) -> VColor { VColor(hex: hex) ?? .white }
}
