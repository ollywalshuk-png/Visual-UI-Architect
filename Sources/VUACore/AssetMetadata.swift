import Foundation

/// Semantic role of an imported asset within a UI. Drives how it becomes a
/// layer when dropped on the canvas, and what control behaviour it implies.
public enum AssetRole: String, Codable, Hashable, Sendable, CaseIterable {
    case backplate         // base panel artwork (sits behind controls)
    case knobCap           // single-image knob (rotated)
    case faderCap          // fader handle/cap
    case faderTrack        // fader rail/track
    case meterLED          // meter element / scale
    case button            // button artwork
    case toggleSwitch      // switch artwork
    case decoration        // pure decoration
    case icon              // glyph / icon
    case texture           // tileable/material texture

    public var displayName: String {
        switch self {
        case .backplate: return "Backplate"
        case .knobCap: return "Knob Cap"
        case .faderCap: return "Fader Cap"
        case .faderTrack: return "Fader Track"
        case .meterLED: return "Meter LED"
        case .button: return "Button"
        case .toggleSwitch: return "Switch"
        case .decoration: return "Decoration"
        case .icon: return "Icon"
        case .texture: return "Texture"
        }
    }
}

/// High-level function the asset performs in a UI.
public enum AssetFunction: String, Codable, Hashable, Sendable, CaseIterable {
    case displayOnly        // purely decorative / informative
    case rotaryControl      // rotated to indicate value
    case linearControl      // moves along an axis
    case pressControl       // momentary press / tap
    case toggleControl      // discrete on/off
}

/// How the user interacts with the asset on the canvas (and at runtime in
/// generated code where supported).
public enum InteractionType: String, Codable, Hashable, Sendable, CaseIterable {
    case none
    case rotaryAbsolute     // pointer follows angle exactly
    case rotaryRelative     // vertical drag adjusts angle relative to start
    case verticalDrag       // up = increase
    case horizontalDrag     // right = increase
    case circularDrag
    case tap
    case press
}

/// Rotation envelope for rotary controls. Sweep is from `minDegrees` to
/// `maxDegrees`, with `zeroDegrees` mapped to the parameter's default.
/// Typical knob: −135 → +135, zero at 0.
public struct RotationBehaviour: Codable, Hashable, Sendable {
    public var minDegrees: Double
    public var maxDegrees: Double
    public var zeroDegrees: Double

    public init(minDegrees: Double = -135, maxDegrees: Double = 135, zeroDegrees: Double = 0) {
        self.minDegrees = minDegrees
        self.maxDegrees = maxDegrees
        self.zeroDegrees = zeroDegrees
    }

    public var sweepDegrees: Double { maxDegrees - minDegrees }

    /// Converts a normalised value (0…1) to an angle in degrees.
    public func angle(forNormalized t: Double) -> Double {
        let clamped = Swift.min(1, Swift.max(0, t))
        return minDegrees + clamped * sweepDegrees
    }
}

/// Drag/axis envelope for linear controls.
public struct DragBehaviour: Codable, Hashable, Sendable {
    public enum Axis: String, Codable, Hashable, Sendable, CaseIterable {
        case vertical, horizontal
    }
    public var axis: Axis
    /// How many on-screen points equal a full 0→1 sweep.
    public var pixelsPerFullSweep: Double
    /// Optional snapping (e.g. detents) in normalised units.
    public var snapStep: Double?

    public init(axis: Axis = .vertical, pixelsPerFullSweep: Double = 200, snapStep: Double? = nil) {
        self.axis = axis
        self.pixelsPerFullSweep = pixelsPerFullSweep
        self.snapStep = snapStep
    }
}

/// Production binding for the asset's parameter — used by code generation,
/// AU/MIDI mapping, and automation export. All fields are optional so partial
/// metadata still saves; diagnostics flag the gaps.
public struct AssetControlBinding: Codable, Hashable, Sendable {
    public var parameterID: String?
    public var displayName: String?
    public var minValue: Double?
    public var maxValue: Double?
    public var defaultValue: Double?
    public var unit: ControlUnit
    public var midiCC: Int?              // 0…127 when set
    public var auParameterID: String?
    public var automationEnabled: Bool
    /// Continuous (knob/slider) vs stepped (switch / 3-way / enum).
    public var isContinuous: Bool
    public var stepCount: Int?

    public init(parameterID: String? = nil, displayName: String? = nil,
                minValue: Double? = nil, maxValue: Double? = nil,
                defaultValue: Double? = nil, unit: ControlUnit = .generic,
                midiCC: Int? = nil, auParameterID: String? = nil,
                automationEnabled: Bool = false,
                isContinuous: Bool = true, stepCount: Int? = nil) {
        self.parameterID = parameterID
        self.displayName = displayName
        self.minValue = minValue
        self.maxValue = maxValue
        self.defaultValue = defaultValue
        self.unit = unit
        self.midiCC = midiCC
        self.auParameterID = auParameterID
        self.automationEnabled = automationEnabled
        self.isContinuous = isContinuous
        self.stepCount = stepCount
    }

    /// Promotes the binding to a fully-populated `ControlMetadata` when enough
    /// fields are set. Returns nil if the binding is too thin.
    public func toControlMetadata() -> ControlMetadata? {
        guard let parameterID, let minValue, let maxValue else { return nil }
        let defaultV = defaultValue ?? minValue
        return ControlMetadata(
            parameterID: parameterID,
            displayName: displayName ?? parameterID,
            minValue: minValue, maxValue: maxValue, defaultValue: defaultV,
            unit: unit, isContinuous: isContinuous, stepCount: stepCount)
    }
}

/// Per-asset metadata describing how the asset should behave when placed.
/// Travels with the `Asset` in `document.json` so projects move between
/// machines with their functional bindings intact.
public struct AssetMetadata: Codable, Hashable, Sendable {
    public var role: AssetRole
    public var function: AssetFunction
    public var interaction: InteractionType
    public var rotation: RotationBehaviour?
    public var drag: DragBehaviour?
    public var binding: AssetControlBinding

    public init(role: AssetRole = .decoration,
                function: AssetFunction = .displayOnly,
                interaction: InteractionType = .none,
                rotation: RotationBehaviour? = nil,
                drag: DragBehaviour? = nil,
                binding: AssetControlBinding = AssetControlBinding()) {
        self.role = role
        self.function = function
        self.interaction = interaction
        self.rotation = rotation
        self.drag = drag
        self.binding = binding
    }

    /// Sensible defaults for a role — only populates behaviour fields that
    /// would otherwise be empty.
    public static func defaults(for role: AssetRole) -> AssetMetadata {
        switch role {
        case .knobCap:
            return AssetMetadata(
                role: .knobCap, function: .rotaryControl, interaction: .rotaryRelative,
                rotation: RotationBehaviour(), drag: nil,
                binding: AssetControlBinding(automationEnabled: true))
        case .faderCap:
            return AssetMetadata(
                role: .faderCap, function: .linearControl, interaction: .verticalDrag,
                rotation: nil, drag: DragBehaviour(axis: .vertical, pixelsPerFullSweep: 180),
                binding: AssetControlBinding(automationEnabled: true))
        case .faderTrack:
            return AssetMetadata(role: .faderTrack, function: .displayOnly, interaction: .none)
        case .meterLED:
            return AssetMetadata(role: .meterLED, function: .displayOnly, interaction: .none,
                                 binding: AssetControlBinding(automationEnabled: true))
        case .button:
            return AssetMetadata(role: .button, function: .pressControl, interaction: .tap,
                                 binding: AssetControlBinding(isContinuous: false, stepCount: 2))
        case .toggleSwitch:
            return AssetMetadata(role: .toggleSwitch, function: .toggleControl, interaction: .tap,
                                 binding: AssetControlBinding(minValue: 0, maxValue: 1,
                                                              defaultValue: 0, isContinuous: false,
                                                              stepCount: 2))
        case .backplate, .decoration, .icon, .texture:
            return AssetMetadata(role: role, function: .displayOnly, interaction: .none)
        }
    }
}
