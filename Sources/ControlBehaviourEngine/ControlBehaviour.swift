import Foundation
import VUACore

public enum ControlBehaviourType: String, Codable, CaseIterable, Hashable, Sendable {
    case rotaryKnob
    case endlessEncoder
    case steppedKnob
    case bipolarKnob
    case verticalFader
    case horizontalSlider
    case buttonPress
    case toggleSwitch
    case meterReadout

    public var displayName: String {
        switch self {
        case .rotaryKnob: return "Rotary Knob"
        case .endlessEncoder: return "Endless Encoder"
        case .steppedKnob: return "Stepped Knob"
        case .bipolarKnob: return "Bipolar Knob"
        case .verticalFader: return "Vertical Fader"
        case .horizontalSlider: return "Horizontal Slider"
        case .buttonPress: return "Button Press"
        case .toggleSwitch: return "Toggle / Switch"
        case .meterReadout: return "Meter Readout"
        }
    }
}

public enum ControlInteractionMode: String, Codable, CaseIterable, Hashable, Sendable {
    case verticalDragRotary
    case circularDragRotary
    case absolute
    case relative
    case steppedSelector
    case bipolarCenter
    case linearDrag
    case press
    case toggle
    case readOnly
}

public enum ControlDragAxis: String, Codable, CaseIterable, Hashable, Sendable {
    case none, vertical, horizontal, circular
}

public enum ControlResponseCurve: String, Codable, CaseIterable, Hashable, Sendable {
    case linear, logarithmic, exponential, bipolar
}

public enum ControlSnapBehaviour: String, Codable, CaseIterable, Hashable, Sendable {
    case none, step, center
}

public struct ControlBehaviourProfile: Codable, Hashable, Sendable {
    public var type: ControlBehaviourType
    public var interactionMode: ControlInteractionMode
    public var dragAxis: ControlDragAxis
    public var rotationStartDegrees: Double
    public var rotationEndDegrees: Double
    public var minValue: Double
    public var maxValue: Double
    public var defaultValue: Double
    public var normalizedValue: Double
    public var unit: ControlUnit
    public var responseCurve: ControlResponseCurve
    public var isContinuous: Bool
    public var stepCount: Int?
    public var snapBehaviour: ControlSnapBehaviour
    public var displayFormatter: String
    public var bindingName: String?
    public var parameterID: String
    public var midiCC: Int?
    public var auParameterID: String?
    public var automationEnabled: Bool

    public init(type: ControlBehaviourType, interactionMode: ControlInteractionMode,
                dragAxis: ControlDragAxis, rotationStartDegrees: Double = -135,
                rotationEndDegrees: Double = 135, minValue: Double = 0,
                maxValue: Double = 1, defaultValue: Double = 0,
                unit: ControlUnit = .generic, responseCurve: ControlResponseCurve = .linear,
                isContinuous: Bool = true, stepCount: Int? = nil,
                snapBehaviour: ControlSnapBehaviour = .none,
                displayFormatter: String = "{value}", bindingName: String? = nil,
                parameterID: String = "value", midiCC: Int? = nil,
                auParameterID: String? = nil, automationEnabled: Bool = false) {
        self.type = type
        self.interactionMode = interactionMode
        self.dragAxis = dragAxis
        self.rotationStartDegrees = rotationStartDegrees
        self.rotationEndDegrees = rotationEndDegrees
        self.minValue = minValue
        self.maxValue = maxValue
        self.defaultValue = defaultValue
        self.normalizedValue = ControlBehaviourMath.normalize(defaultValue, min: minValue, max: maxValue)
        self.unit = unit
        self.responseCurve = responseCurve
        self.isContinuous = isContinuous
        self.stepCount = stepCount
        self.snapBehaviour = snapBehaviour
        self.displayFormatter = displayFormatter
        self.bindingName = bindingName
        self.parameterID = parameterID
        self.midiCC = midiCC
        self.auParameterID = auParameterID
        self.automationEnabled = automationEnabled
    }

    public func clamped(_ value: Double) -> Double {
        ControlBehaviourMath.clamp(value, min: minValue, max: maxValue, stepCount: isContinuous ? nil : stepCount)
    }
}

public enum ControlBehaviourMath {
    public static func normalize(_ value: Double, min: Double, max: Double) -> Double {
        guard max > min else { return 0 }
        return Swift.min(1, Swift.max(0, (value - min) / (max - min)))
    }

    public static func denormalize(_ value: Double, min: Double, max: Double) -> Double {
        min + Swift.min(1, Swift.max(0, value)) * (max - min)
    }

    public static func clamp(_ value: Double, min: Double, max: Double, stepCount: Int? = nil) -> Double {
        let clamped = Swift.min(max, Swift.max(min, value))
        guard let stepCount, stepCount > 1, max > min else { return clamped }
        let step = (max - min) / Double(stepCount - 1)
        let index = ((clamped - min) / step).rounded()
        return min + index * step
    }
}

public enum ControlBehaviourResolver {
    public static func profile(for layer: Layer) -> ControlBehaviourProfile? {
        guard let control = layer.control else { return nil }
        let type = explicitType(control) ?? inferredType(for: layer)
        let interaction = explicitInteraction(control, type: type)
        let curve = ControlResponseCurve(rawValue: control.responseCurve ?? "") ?? defaultCurve(for: type)
        let stepCount = resolvedStepCount(type: type, control: control)
        return ControlBehaviourProfile(
            type: type,
            interactionMode: interaction,
            dragAxis: dragAxis(for: type),
            rotationStartDegrees: control.rotationStartDegrees ?? defaultRotation(type).0,
            rotationEndDegrees: control.rotationEndDegrees ?? defaultRotation(type).1,
            minValue: control.minValue,
            maxValue: control.maxValue,
            defaultValue: control.clamp(control.defaultValue),
            unit: control.unit,
            responseCurve: curve,
            isContinuous: isContinuous(type: type, control: control),
            stepCount: stepCount,
            snapBehaviour: snapBehaviour(type: type),
            displayFormatter: formatter(for: control),
            bindingName: control.bindingName,
            parameterID: control.parameterID,
            midiCC: control.midiCC,
            auParameterID: control.auParameterID,
            automationEnabled: control.automationEnabled ?? false)
    }

    public static func defaultMetadata(for kind: LayerKind, name: String) -> ControlMetadata? {
        switch kind {
        case .knob:
            return ControlMetadata(parameterID: "parameter", displayName: name,
                                   minValue: 0, maxValue: 100, defaultValue: 50,
                                   unit: .percent, behaviourType: ControlBehaviourType.rotaryKnob.rawValue,
                                   interactionMode: ControlInteractionMode.verticalDragRotary.rawValue,
                                   responseCurve: ControlResponseCurve.linear.rawValue,
                                   automationEnabled: true, rotationStartDegrees: -135,
                                   rotationEndDegrees: 135)
        case .fader:
            return ControlMetadata(parameterID: "level", displayName: name,
                                   minValue: -60, maxValue: 6, defaultValue: 0,
                                   unit: .decibels, behaviourType: ControlBehaviourType.verticalFader.rawValue,
                                   interactionMode: ControlInteractionMode.linearDrag.rawValue,
                                   responseCurve: ControlResponseCurve.linear.rawValue,
                                   automationEnabled: true)
        case .slider:
            return ControlMetadata(parameterID: "value", displayName: name,
                                   minValue: 0, maxValue: 100, defaultValue: 50,
                                   unit: .percent, behaviourType: ControlBehaviourType.horizontalSlider.rawValue,
                                   interactionMode: ControlInteractionMode.linearDrag.rawValue,
                                   responseCurve: ControlResponseCurve.linear.rawValue,
                                   automationEnabled: true)
        case .button:
            return ControlMetadata(parameterID: "trigger", displayName: name,
                                   minValue: 0, maxValue: 1, defaultValue: 0,
                                   unit: .generic, isContinuous: false, stepCount: 2,
                                   behaviourType: ControlBehaviourType.buttonPress.rawValue,
                                   interactionMode: ControlInteractionMode.press.rawValue)
        case .toggle:
            return ControlMetadata(parameterID: "enabled", displayName: name,
                                   minValue: 0, maxValue: 1, defaultValue: 1,
                                   unit: .generic, isContinuous: false, stepCount: 2,
                                   behaviourType: ControlBehaviourType.toggleSwitch.rawValue,
                                   interactionMode: ControlInteractionMode.toggle.rawValue,
                                   automationEnabled: true)
        case .meter:
            return ControlMetadata(parameterID: "level", displayName: name,
                                   minValue: -60, maxValue: 0, defaultValue: -18,
                                   unit: .decibels, behaviourType: ControlBehaviourType.meterReadout.rawValue,
                                   interactionMode: ControlInteractionMode.readOnly.rawValue)
        default:
            return nil
        }
    }

    private static func explicitType(_ control: ControlMetadata) -> ControlBehaviourType? {
        control.behaviourType.flatMap(ControlBehaviourType.init(rawValue:))
    }

    private static func inferredType(for layer: Layer) -> ControlBehaviourType {
        switch layer.kind {
        case .knob:
            if layer.control?.isContinuous == false { return .steppedKnob }
            if (layer.control?.minValue ?? 0) < 0 && (layer.control?.maxValue ?? 0) > 0 { return .bipolarKnob }
            return .rotaryKnob
        case .fader: return .verticalFader
        case .slider: return .horizontalSlider
        case .button: return .buttonPress
        case .toggle: return .toggleSwitch
        case .meter: return .meterReadout
        default: return .horizontalSlider
        }
    }

    private static func explicitInteraction(_ control: ControlMetadata, type: ControlBehaviourType) -> ControlInteractionMode {
        if let raw = control.interactionMode, let mode = ControlInteractionMode(rawValue: raw) { return mode }
        switch type {
        case .rotaryKnob: return .verticalDragRotary
        case .endlessEncoder: return .relative
        case .steppedKnob: return .steppedSelector
        case .bipolarKnob: return .bipolarCenter
        case .verticalFader, .horizontalSlider: return .linearDrag
        case .buttonPress: return .press
        case .toggleSwitch: return .toggle
        case .meterReadout: return .readOnly
        }
    }

    private static func dragAxis(for type: ControlBehaviourType) -> ControlDragAxis {
        switch type {
        case .rotaryKnob, .steppedKnob, .bipolarKnob: return .vertical
        case .endlessEncoder: return .circular
        case .verticalFader: return .vertical
        case .horizontalSlider: return .horizontal
        case .buttonPress, .toggleSwitch, .meterReadout: return .none
        }
    }

    private static func defaultRotation(_ type: ControlBehaviourType) -> (Double, Double) {
        switch type {
        case .endlessEncoder: return (-180, 180)
        case .buttonPress, .toggleSwitch, .meterReadout, .verticalFader, .horizontalSlider: return (0, 0)
        default: return (-135, 135)
        }
    }

    private static func defaultCurve(for type: ControlBehaviourType) -> ControlResponseCurve {
        switch type {
        case .bipolarKnob: return .bipolar
        default: return .linear
        }
    }

    private static func isContinuous(type: ControlBehaviourType, control: ControlMetadata) -> Bool {
        switch type {
        case .buttonPress, .toggleSwitch, .steppedKnob: return false
        case .meterReadout: return true
        default: return control.isContinuous
        }
    }

    private static func resolvedStepCount(type: ControlBehaviourType, control: ControlMetadata) -> Int? {
        switch type {
        case .buttonPress, .toggleSwitch: return control.stepCount ?? 2
        case .steppedKnob: return control.stepCount ?? 12
        default: return control.stepCount
        }
    }

    private static func snapBehaviour(type: ControlBehaviourType) -> ControlSnapBehaviour {
        switch type {
        case .buttonPress, .toggleSwitch, .steppedKnob: return .step
        case .bipolarKnob: return .center
        default: return .none
        }
    }

    private static func formatter(for control: ControlMetadata) -> String {
        control.unit.symbol.isEmpty ? "{value}" : "{value} \(control.unit.symbol)"
    }
}

public enum ControlBehaviourDiagnostics {
    public enum Code: String, Sendable {
        case missingBehaviour
        case invalidRange
        case defaultOutOfRange
        case missingSteps
        case invalidMIDI
        case meterMustBeReadOnly
        case invalidRotation
        case unboundAutomation
    }

    public struct Issue: Identifiable, Hashable, Sendable {
        public let id = UUID()
        public var code: Code
        public var message: String
        public var layerID: UUID
    }

    public static func validate(_ layer: Layer) -> [Issue] {
        guard let control = layer.control else {
            return layer.kind.isPluginControl
                ? [Issue(code: .missingBehaviour, message: "'\(layer.name)' has no behaviour metadata.", layerID: layer.id)]
                : []
        }
        guard let profile = ControlBehaviourResolver.profile(for: layer) else { return [] }
        var out: [Issue] = []
        if profile.maxValue <= profile.minValue {
            out.append(Issue(code: .invalidRange, message: "'\(layer.name)' has an empty or inverted range.", layerID: layer.id))
        }
        if control.defaultValue < control.minValue || control.defaultValue > control.maxValue {
            out.append(Issue(code: .defaultOutOfRange, message: "'\(layer.name)' default is outside min/max.", layerID: layer.id))
        }
        if !profile.isContinuous && profile.stepCount == nil {
            out.append(Issue(code: .missingSteps, message: "'\(layer.name)' is stepped but has no step count.", layerID: layer.id))
        }
        if let cc = profile.midiCC, cc < 0 || cc > 127 {
            out.append(Issue(code: .invalidMIDI, message: "'\(layer.name)' MIDI CC must be 0...127.", layerID: layer.id))
        }
        if profile.type == .meterReadout && profile.interactionMode != .readOnly {
            out.append(Issue(code: .meterMustBeReadOnly, message: "'\(layer.name)' meter behaviour must be read-only.", layerID: layer.id))
        }
        if profile.rotationEndDegrees < profile.rotationStartDegrees {
            out.append(Issue(code: .invalidRotation, message: "'\(layer.name)' rotation end is before start.", layerID: layer.id))
        }
        if profile.automationEnabled && profile.parameterID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.append(Issue(code: .unboundAutomation, message: "'\(layer.name)' is automation-enabled but has no parameter id.", layerID: layer.id))
        }
        return out
    }
}
