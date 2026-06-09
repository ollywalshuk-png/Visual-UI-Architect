import Foundation
import VUACore

/// Builds the AU parameter manifest from layers carrying `ControlMetadata`,
/// and produces diagnostics for placeholder/unbound controls.
public enum ParameterPlanner {

    public struct Plan: Sendable {
        public var parameters: [ParameterEntry]
        public var diagnostics: [ExportDiagnostic]
    }

    public static func plan(document: Document) -> Plan {
        var parameters: [ParameterEntry] = []
        var diagnostics: [ExportDiagnostic] = []

        for layer in document.allLayers where layer.kind.isPluginControl {
            guard let meta = layer.control else {
                diagnostics.append(ExportDiagnostic(
                    severity: .warning, code: .controlNotProductionBound,
                    message: "Control '\(layer.name)' has no parameter metadata.",
                    detail: "Bind it via the AU Parameter section of the inspector."))
                continue
            }
            let placeholder = isPlaceholder(meta)
            if placeholder {
                diagnostics.append(ExportDiagnostic(
                    severity: .warning, code: .placeholderParameter,
                    message: "Control '\(layer.name)' uses placeholder parameter '\(meta.parameterID)'.",
                    detail: "Set a unique parameter id and review min/max/default before shipping."))
            }
            if layer.binding == nil {
                diagnostics.append(ExportDiagnostic(
                    severity: .warning, code: .controlNotProductionBound,
                    message: "Control '\(layer.name)' has no anchor binding.",
                    detail: "Round-trip editing requires an accessibilityIdentifier."))
            }
            parameters.append(ParameterEntry(
                layerID: layer.id,
                parameterID: meta.parameterID,
                displayName: meta.displayName,
                minValue: meta.minValue,
                maxValue: meta.maxValue,
                defaultValue: meta.defaultValue,
                unit: meta.unit.symbol.isEmpty ? meta.unit.rawValue : meta.unit.symbol,
                isContinuous: meta.isContinuous,
                stepCount: meta.stepCount,
                midiCC: nil,
                automationEnabled: true,
                isPlaceholder: placeholder
            ))
        }
        return Plan(parameters: parameters, diagnostics: diagnostics)
    }

    /// Heuristic: metadata that still matches the document's defaults — same
    /// parameter id as the layer kind, default at min, etc. — is treated as
    /// unreviewed.
    public static func isPlaceholder(_ meta: ControlMetadata) -> Bool {
        let knownDefaults: Set<String> = ["cutoff", "level", "mix", "output", "enabled"]
        let defaultLikeID = knownDefaults.contains(meta.parameterID.lowercased())
        let displayMatchesID = meta.displayName.lowercased() == meta.parameterID.lowercased()
        return defaultLikeID && displayMatchesID
    }
}
