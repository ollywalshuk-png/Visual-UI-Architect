import Foundation
import VUACore

public enum BehaviourBindingKind: String, Codable, Hashable, Sendable {
    case value
    case toggle
    case action
    case readOnly
    case navigation
    case modal
}

public enum BehaviourValueType: String, Codable, Hashable, Sendable {
    case double
    case bool
    case void
}

public struct BehaviourBinding: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID { layerID }
    public var layerID: UUID
    public var layerName: String
    public var kind: BehaviourBindingKind
    public var valueType: BehaviourValueType
    public var propertyName: String?
    public var actionName: String?
    public var parameterID: String
    public var minValue: Double
    public var maxValue: Double
    public var defaultValue: Double
    public var unit: ControlUnit
    public var midiCC: Int?
    public var auParameterID: String?
    public var automationEnabled: Bool
    public var sourceAnchorID: String?
}

public struct BehaviourViewModelPlan: Codable, Hashable, Sendable {
    public var viewModelName: String
    public var bindings: [BehaviourBinding]

    public var stateBindings: [BehaviourBinding] {
        bindings.filter { $0.propertyName != nil }
    }

    public var actionBindings: [BehaviourBinding] {
        bindings.filter { $0.actionName != nil }
    }

    public var midiBindings: [BehaviourBinding] {
        bindings.filter { $0.midiCC != nil }
    }

    public var auParameterBindings: [BehaviourBinding] {
        bindings.filter { $0.auParameterID != nil }
    }
}

/// Phase 48: converts visual control behaviour metadata into a binding plan
/// that later generators can use for real ViewModels instead of placeholder
/// comments. It is intentionally independent from SwiftUI rendering.
public enum BehaviourBindingPlanner {
    public static func plan(for document: Document, viewModelName: String? = nil) -> BehaviourViewModelPlan {
        let name = viewModelName ?? "\(safeType(document.name))ViewModel"
        let bindings = document.allLayers.compactMap(binding(for:))
        return BehaviourViewModelPlan(viewModelName: name, bindings: uniqued(bindings))
    }

    private static func binding(for layer: Layer) -> BehaviourBinding? {
        let hasExplicitControl = layer.control != nil
        let metadata = layer.control ?? ControlBehaviourResolver.defaultMetadata(for: layer.kind, name: layer.name)
        guard let metadata else { return nil }
        var probe = layer
        probe.control = metadata
        guard let profile = ControlBehaviourResolver.profile(for: probe) else { return nil }

        let baseName = metadata.bindingName?.nilIfBlank
            ?? (!hasExplicitControl ? layer.binding?.anchorID.nilIfBlank : nil)
            ?? metadata.parameterID.nilIfBlank
            ?? layer.name
        let property = propertyName(for: profile, layer: layer, baseName: baseName)
        let action = actionName(for: profile, layer: layer, baseName: baseName)
        return BehaviourBinding(
            layerID: layer.id,
            layerName: layer.name,
            kind: bindingKind(for: profile, layer: layer),
            valueType: valueType(for: profile),
            propertyName: property,
            actionName: action,
            parameterID: profile.parameterID,
            minValue: profile.minValue,
            maxValue: profile.maxValue,
            defaultValue: profile.defaultValue,
            unit: profile.unit,
            midiCC: profile.midiCC,
            auParameterID: profile.auParameterID,
            automationEnabled: profile.automationEnabled,
            sourceAnchorID: layer.binding?.anchorID)
    }

    private static func bindingKind(for profile: ControlBehaviourProfile, layer: Layer) -> BehaviourBindingKind {
        if layer.role == .navigation || layer.tags.contains(where: { $0.localizedCaseInsensitiveContains("navigation") }) {
            return .navigation
        }
        if layer.tags.contains(where: { $0.localizedCaseInsensitiveContains("modal") || $0.localizedCaseInsensitiveContains("sheet") }) {
            return .modal
        }
        switch profile.type {
        case .buttonPress: return .action
        case .toggleSwitch: return .toggle
        case .meterReadout, .valueDisplay: return .readOnly
        default: return .value
        }
    }

    private static func valueType(for profile: ControlBehaviourProfile) -> BehaviourValueType {
        switch profile.type {
        case .buttonPress: return .void
        case .toggleSwitch: return .bool
        default: return .double
        }
    }

    private static func propertyName(for profile: ControlBehaviourProfile, layer: Layer, baseName: String) -> String? {
        switch bindingKind(for: profile, layer: layer) {
        case .action, .navigation, .modal:
            return nil
        case .toggle, .value, .readOnly:
            return safeVar(baseName)
        }
    }

    private static func actionName(for profile: ControlBehaviourProfile, layer: Layer, baseName: String) -> String? {
        switch bindingKind(for: profile, layer: layer) {
        case .action:
            return safeVar(baseName + " action")
        case .navigation:
            return safeVar("navigate " + baseName)
        case .modal:
            return safeVar("present " + baseName)
        case .value, .toggle, .readOnly:
            return nil
        }
    }

    private static func uniqued(_ bindings: [BehaviourBinding]) -> [BehaviourBinding] {
        var seenProperties: Set<String> = []
        var seenActions: Set<String> = []
        return bindings.map { binding in
            var copy = binding
            if let property = copy.propertyName {
                copy.propertyName = unique(property, in: &seenProperties)
            }
            if let action = copy.actionName {
                copy.actionName = unique(action, in: &seenActions)
            }
            return copy
        }
    }

    private static func unique(_ name: String, in seen: inout Set<String>) -> String {
        if !seen.contains(name) {
            seen.insert(name)
            return name
        }
        var index = 2
        while seen.contains("\(name)\(index)") { index += 1 }
        let value = "\(name)\(index)"
        seen.insert(value)
        return value
    }
}

public enum BehaviourViewModelGenerator {
    public static func generateSwiftObservableObject(plan: BehaviourViewModelPlan) -> String {
        var lines: [String] = []
        lines.append("import Foundation")
        lines.append("import Combine")
        lines.append("")
        lines.append("final class \(safeType(plan.viewModelName)): ObservableObject {")
        for binding in plan.stateBindings {
            lines.append("    @Published var \(binding.propertyName!): \(swiftType(binding.valueType)) = \(swiftDefault(binding))")
        }
        if !plan.stateBindings.isEmpty && !plan.actionBindings.isEmpty { lines.append("") }
        for binding in plan.actionBindings {
            lines.append("    func \(binding.actionName!)() {")
            lines.append("        // TODO: connect \(binding.layerName) to app behaviour.")
            lines.append("    }")
        }
        if !plan.bindings.isEmpty {
            lines.append("")
            lines.append("    struct BindingDescriptor: Identifiable, Hashable {")
            lines.append("        let id: String")
            lines.append("        let layerID: String")
            lines.append("        let anchorID: String?")
            lines.append("        let layerName: String")
            lines.append("        let kind: String")
            lines.append("        let valueType: String")
            lines.append("        let parameterID: String")
            lines.append("        let propertyName: String?")
            lines.append("        let actionName: String?")
            lines.append("        let midiCC: Int?")
            lines.append("        let auParameterID: String?")
            lines.append("        let automationEnabled: Bool")
            lines.append("        let minValue: Double")
            lines.append("        let maxValue: Double")
            lines.append("        let defaultValue: Double")
            lines.append("        let unit: String")
            lines.append("    }")
            lines.append("")
            lines.append("    let bindingDescriptors: [BindingDescriptor] = [")
            for binding in plan.bindings {
                lines.append("        \(descriptorLiteral(binding)),")
            }
            lines.append("    ]")
            lines.append("")
            lines.append("    var automationParameterIDs: [String] {")
            lines.append("        bindingDescriptors.filter(\\.automationEnabled).map(\\.parameterID)")
            lines.append("    }")
            lines.append("")
            lines.append("    func binding(forParameterID parameterID: String) -> BindingDescriptor? {")
            lines.append("        bindingDescriptors.first { $0.parameterID == parameterID }")
            lines.append("    }")
            lines.append("")
            lines.append("    func binding(forMIDI cc: Int) -> BindingDescriptor? {")
            lines.append("        bindingDescriptors.first { $0.midiCC == cc }")
            lines.append("    }")
            lines.append("")
            lines.append("    func binding(forAUParameterID auParameterID: String) -> BindingDescriptor? {")
            lines.append("        bindingDescriptors.first { $0.auParameterID == auParameterID }")
            lines.append("    }")
            emitSetters(plan: plan, into: &lines)
            emitActionDispatcher(plan: plan, into: &lines)
        }
        if !plan.midiBindings.isEmpty {
            lines.append("")
            lines.append("    let midiCCMap: [String: Int] = [")
            for binding in plan.midiBindings {
                lines.append("        \"\(binding.parameterID)\": \(binding.midiCC!),")
            }
            lines.append("    ]")
        }
        if !plan.auParameterBindings.isEmpty {
            lines.append("")
            lines.append("    let auParameterMap: [String: String] = [")
            for binding in plan.auParameterBindings {
                lines.append("        \"\(binding.parameterID)\": \"\(binding.auParameterID!)\",")
            }
            lines.append("    ]")
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func swiftType(_ type: BehaviourValueType) -> String {
        switch type {
        case .double: return "Double"
        case .bool: return "Bool"
        case .void: return "Void"
        }
    }

    private static func swiftDefault(_ binding: BehaviourBinding) -> String {
        switch binding.valueType {
        case .bool: return binding.defaultValue >= 0.5 ? "true" : "false"
        case .double: return format(binding.defaultValue)
        case .void: return "()"
        }
    }

    private static func descriptorLiteral(_ binding: BehaviourBinding) -> String {
        [
            "BindingDescriptor(id: \(swiftString(binding.layerID.uuidString))",
            "layerID: \(swiftString(binding.layerID.uuidString))",
            "anchorID: \(optionalString(binding.sourceAnchorID))",
            "layerName: \(swiftString(binding.layerName))",
            "kind: \(swiftString(binding.kind.rawValue))",
            "valueType: \(swiftString(binding.valueType.rawValue))",
            "parameterID: \(swiftString(binding.parameterID))",
            "propertyName: \(optionalString(binding.propertyName))",
            "actionName: \(optionalString(binding.actionName))",
            "midiCC: \(binding.midiCC.map(String.init) ?? "nil")",
            "auParameterID: \(optionalString(binding.auParameterID))",
            "automationEnabled: \(binding.automationEnabled ? "true" : "false")",
            "minValue: \(format(binding.minValue))",
            "maxValue: \(format(binding.maxValue))",
            "defaultValue: \(format(binding.defaultValue))",
            "unit: \(swiftString(binding.unit.rawValue)))"
        ].joined(separator: ", ")
    }

    private static func emitSetters(plan: BehaviourViewModelPlan, into lines: inout [String]) {
        let doubleBindings = plan.stateBindings.filter { $0.valueType == .double }
        let boolBindings = plan.stateBindings.filter { $0.valueType == .bool }
        guard !doubleBindings.isEmpty || !boolBindings.isEmpty else { return }

        if !doubleBindings.isEmpty {
            lines.append("")
            lines.append("    func setDouble(_ propertyName: String, value: Double) {")
            lines.append("        switch propertyName {")
            for binding in doubleBindings {
                guard let property = binding.propertyName else { continue }
                lines.append("        case \(swiftString(property)):")
                lines.append("            \(property) = min(\(format(binding.maxValue)), max(\(format(binding.minValue)), value))")
            }
            lines.append("        default:")
            lines.append("            break")
            lines.append("        }")
            lines.append("    }")
        }

        if !boolBindings.isEmpty {
            lines.append("")
            lines.append("    func setBool(_ propertyName: String, value: Bool) {")
            lines.append("        switch propertyName {")
            for binding in boolBindings {
                guard let property = binding.propertyName else { continue }
                lines.append("        case \(swiftString(property)):")
                lines.append("            \(property) = value")
            }
            lines.append("        default:")
            lines.append("            break")
            lines.append("        }")
            lines.append("    }")
        }
    }

    private static func emitActionDispatcher(plan: BehaviourViewModelPlan, into lines: inout [String]) {
        guard !plan.actionBindings.isEmpty else { return }
        lines.append("")
        lines.append("    func perform(action actionName: String) {")
        lines.append("        switch actionName {")
        for binding in plan.actionBindings {
            guard let action = binding.actionName else { continue }
            lines.append("        case \(swiftString(action)):")
            lines.append("            \(action)()")
        }
        lines.append("        default:")
        lines.append("            break")
        lines.append("        }")
        lines.append("    }")
    }

    private static func optionalString(_ value: String?) -> String {
        value.map(swiftString) ?? "nil"
    }

    private static func swiftString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}

private func safeType(_ raw: String) -> String {
    let parts = raw.split { !$0.isLetter && !$0.isNumber && $0 != "_" }
    let joined = parts.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    let value = joined.isEmpty ? "GeneratedViewModel" : joined
    return value.first?.isNumber == true ? "VUA\(value)" : value
}

private func safeVar(_ raw: String) -> String {
    let type = safeType(raw)
    guard let first = type.first else { return "value" }
    return first.lowercased() + type.dropFirst()
}

private func format(_ value: Double) -> String {
    if abs(value - value.rounded()) < 0.000_001 { return String(Int(value.rounded())) }
    return String(format: "%.3f", value).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
