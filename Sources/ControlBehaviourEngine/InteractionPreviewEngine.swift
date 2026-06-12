import Foundation
import VUACore

public enum EditorInteractionMode: String, Codable, CaseIterable, Hashable, Sendable {
    case build
    case test

    public var displayName: String {
        switch self {
        case .build: return "Build"
        case .test: return "Test"
        }
    }

    public var allowsLayoutEditing: Bool { self == .build }
    public var allowsFunctionalInteraction: Bool { self == .test }
}

public enum InteractionFunctionalStatus: String, Codable, Hashable, Sendable {
    case functional
    case partiallyFunctional
    case visualOnly
    case missingBehaviour

    public var displayName: String {
        switch self {
        case .functional: return "Functional"
        case .partiallyFunctional: return "Partially Functional"
        case .visualOnly: return "Visual Only"
        case .missingBehaviour: return "Missing Behaviour"
        }
    }
}

public struct InteractionPreviewState: Hashable, Sendable {
    public var mode: EditorInteractionMode
    public var values: [UUID: Double]
    public var activeLayerID: UUID?

    public init(mode: EditorInteractionMode = .build, values: [UUID: Double] = [:], activeLayerID: UUID? = nil) {
        self.mode = mode
        self.values = values
        self.activeLayerID = activeLayerID
    }

    public var isLayoutLocked: Bool { !mode.allowsLayoutEditing }

    public mutating func switchMode(_ newMode: EditorInteractionMode) {
        mode = newMode
        activeLayerID = nil
    }

    public mutating func resetAll() {
        values.removeAll()
        activeLayerID = nil
    }

    public mutating func reset(layerID: UUID) {
        values.removeValue(forKey: layerID)
        if activeLayerID == layerID { activeLayerID = nil }
    }
}

public struct InteractionPreviewResult: Hashable, Sendable {
    public var value: Double
    public var normalizedValue: Double
    public var rotationDegrees: Double?
    public var displayText: String
    public var isActive: Bool
}

public enum InteractionPreviewEngine {
    public static func status(for layer: Layer) -> InteractionFunctionalStatus {
        guard supportsInteraction(layer.kind) else { return .visualOnly }
        guard let profile = ControlBehaviourResolver.profile(for: layer) else { return .missingBehaviour }
        let issues = ControlBehaviourDiagnostics.validate(layer)
        if issues.contains(where: { [.invalidRange, .defaultOutOfRange, .invalidRotation, .meterMustBeReadOnly].contains($0.code) }) {
            return .partiallyFunctional
        }
        if profile.bindingName == nil || profile.bindingName?.isEmpty == true {
            return .partiallyFunctional
        }
        return .functional
    }

    public static func supportsInteraction(_ kind: LayerKind) -> Bool {
        switch kind {
        case .knob, .fader, .slider, .button, .toggle, .meter, .control:
            return true
        default:
            return false
        }
    }

    public static func defaultValue(for layer: Layer) -> Double? {
        ControlBehaviourResolver.profile(for: layer)?.defaultValue
    }

    public static func previewResult(for layer: Layer, state: InteractionPreviewState) -> InteractionPreviewResult? {
        guard let profile = ControlBehaviourResolver.profile(for: layer) else { return nil }
        let value = state.values[layer.id] ?? profile.defaultValue
        return InteractionPreviewResult(
            value: value,
            normalizedValue: ControlBehaviourMath.normalize(value, min: profile.minValue, max: profile.maxValue),
            rotationDegrees: rotationDegrees(for: value, profile: profile),
            displayText: displayString(value, profile: profile),
            isActive: state.activeLayerID == layer.id)
    }

    public static func setValue(_ value: Double, for layer: Layer, in state: inout InteractionPreviewState) {
        guard let profile = ControlBehaviourResolver.profile(for: layer) else { return }
        state.values[layer.id] = profile.clamped(value)
        state.activeLayerID = layer.id
    }

    public static func resetValue(for layer: Layer, in state: inout InteractionPreviewState) {
        state.reset(layerID: layer.id)
    }

    public static func dragValue(for layer: Layer, startingValue: Double, translation: VPoint, fineAdjustment: Bool = false) -> Double? {
        guard let profile = ControlBehaviourResolver.profile(for: layer), profile.interactionMode != .readOnly else { return nil }
        let scale = fineAdjustment ? 0.2 : 1
        let normalized = ControlBehaviourMath.normalize(startingValue, min: profile.minValue, max: profile.maxValue)
        let delta: Double
        switch profile.dragAxis {
        case .vertical:
            let travel = max(60, layer.frame.height * (layer.kind == .knob ? 2 : 1))
            delta = -translation.y / travel
        case .horizontal:
            delta = translation.x / max(1, layer.frame.width)
        case .circular:
            delta = -translation.y / max(60, layer.frame.height * 2)
        case .none:
            return nil
        }
        return value(fromNormalized: normalized + delta * scale, profile: profile)
    }

    public static func linearValue(for layer: Layer, localPoint: VPoint) -> Double? {
        guard let profile = ControlBehaviourResolver.profile(for: layer), profile.interactionMode != .readOnly else { return nil }
        let normalized: Double
        switch profile.dragAxis {
        case .horizontal:
            normalized = localPoint.x / max(1, layer.frame.width)
        case .vertical:
            normalized = 1 - localPoint.y / max(1, layer.frame.height)
        case .circular, .none:
            return nil
        }
        return value(fromNormalized: normalized, profile: profile)
    }

    public static func rotaryValue(for layer: Layer, localPoint: VPoint) -> Double? {
        guard let profile = ControlBehaviourResolver.profile(for: layer),
              [.rotaryKnob, .steppedKnob, .bipolarKnob, .endlessEncoder].contains(profile.type) else { return nil }
        let center = VPoint(x: layer.frame.width / 2, y: layer.frame.height / 2)
        let angle = atan2(localPoint.y - center.y, localPoint.x - center.x) * 180 / Double.pi
        let clampedAngle = min(profile.rotationEndDegrees, max(profile.rotationStartDegrees, angle))
        let span = max(1, profile.rotationEndDegrees - profile.rotationStartDegrees)
        return value(fromNormalized: (clampedAngle - profile.rotationStartDegrees) / span, profile: profile)
    }

    public static func pressedValue(for layer: Layer, isPressed: Bool) -> Double? {
        guard let profile = ControlBehaviourResolver.profile(for: layer), profile.type == .buttonPress else { return nil }
        return isPressed ? profile.maxValue : profile.defaultValue
    }

    public static func toggledValue(for layer: Layer, currentValue: Double) -> Double? {
        guard let profile = ControlBehaviourResolver.profile(for: layer), profile.type == .toggleSwitch else { return nil }
        let normalized = ControlBehaviourMath.normalize(currentValue, min: profile.minValue, max: profile.maxValue)
        return normalized >= 0.5 ? profile.minValue : profile.maxValue
    }

    public static func demoMeterValue(for layer: Layer, time: Double, phase: Double = 0) -> Double? {
        guard let profile = ControlBehaviourResolver.profile(for: layer), profile.type == .meterReadout else { return nil }
        let wave = (sin(time * 1.7 + phase) + 1) / 2
        let shaped = pow(wave, 1.7)
        return value(fromNormalized: shaped, profile: profile)
    }

    public static func displayString(_ value: Double, profile: ControlBehaviourProfile) -> String {
        let formatted: String
        if abs(value) >= 100 {
            formatted = String(format: "%.0f", value)
        } else if abs(value) >= 10 {
            formatted = String(format: "%.1f", value)
        } else {
            formatted = String(format: "%.2f", value)
        }
        if profile.unit.symbol.isEmpty { return formatted }
        return "\(formatted) \(profile.unit.symbol)"
    }

    public static func rotationDegrees(for value: Double, profile: ControlBehaviourProfile) -> Double? {
        guard [.rotaryKnob, .steppedKnob, .bipolarKnob, .endlessEncoder].contains(profile.type) else { return nil }
        let normalized = ControlBehaviourMath.normalize(value, min: profile.minValue, max: profile.maxValue)
        return profile.rotationStartDegrees + normalized * (profile.rotationEndDegrees - profile.rotationStartDegrees)
    }

    private static func value(fromNormalized normalized: Double, profile: ControlBehaviourProfile) -> Double {
        let clamped = min(1, max(0, normalized))
        let value = ControlBehaviourMath.denormalize(clamped, min: profile.minValue, max: profile.maxValue)
        return profile.clamped(value)
    }
}

public extension ControlBehaviourDiagnostics {
    static func validatePreview(_ layer: Layer) -> [Issue] {
        var out = validate(layer)
        guard InteractionPreviewEngine.supportsInteraction(layer.kind) else { return out }
        guard let profile = ControlBehaviourResolver.profile(for: layer) else { return out }
        if profile.bindingName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            out.append(Issue(code: .missingBinding, message: "'\(layer.name)' has no generated binding target.", layerID: layer.id))
        }
        switch profile.type {
        case .horizontalSlider where layer.frame.height > layer.frame.width:
            out.append(Issue(code: .geometryMismatch, message: "'\(layer.name)' is horizontal but taller than it is wide.", layerID: layer.id))
        case .verticalFader where layer.frame.width > layer.frame.height:
            out.append(Issue(code: .geometryMismatch, message: "'\(layer.name)' is vertical but wider than it is tall.", layerID: layer.id))
        case .meterReadout where profile.interactionMode != .readOnly:
            out.append(Issue(code: .writeableMeter, message: "'\(layer.name)' meter should be read-only in Test Mode.", layerID: layer.id))
        default:
            break
        }
        return out
    }
}
