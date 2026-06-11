import Foundation
import VUACore

/// Lint-style diagnostics for `AssetMetadata`: flags partial bindings, range /
/// MIDI / step issues, and mismatches between role and binding so a user
/// shipping plugin/AU artwork has a clear "what's missing" report.
public enum AssetMetadataDiagnostics {

    public struct Issue: Hashable, Sendable, Identifiable {
        public enum Severity: Int, Comparable, Sendable {
            case info, warning, error
            public static func < (l: Severity, r: Severity) -> Bool { l.rawValue < r.rawValue }
        }
        public enum Code: String, Sendable {
            case missingMetadata
            case missingParameterID
            case missingRange
            case invalidRange          // min > max, or min == max
            case defaultOutOfRange
            case midiCCOutOfRange
            case missingSteps          // stepped binding without stepCount
            case roleFunctionMismatch  // role implies a function we didn't get
        }
        public let id = UUID()
        public var severity: Severity
        public var code: Code
        public var message: String
        public var assetID: UUID
    }

    /// Runs the full diagnostic suite for one asset.
    public static func validate(_ asset: Asset) -> [Issue] {
        guard let meta = asset.metadata else {
            // No metadata is only worth reporting for assets that clearly look
            // functional (their role tag hints at a control).
            let hint = asset.tags.contains { ["knob", "fader", "meter", "button", "switch"].contains($0.lowercased()) }
            return hint ? [issue(.warning, .missingMetadata,
                                 "Asset '\(asset.name)' is tagged as a control but has no metadata.",
                                 assetID: asset.id)] : []
        }
        var out: [Issue] = []
        // Functional roles need a parameter id + range.
        let needsBinding: Bool = {
            switch meta.function { case .displayOnly: return false; default: return true }
        }()
        if needsBinding {
            if (meta.binding.parameterID ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                out.append(issue(.error, .missingParameterID,
                                 "Asset '\(asset.name)' has no parameter id.", assetID: asset.id))
            }
            if meta.binding.minValue == nil || meta.binding.maxValue == nil {
                out.append(issue(.error, .missingRange,
                                 "Asset '\(asset.name)' has no min/max range.", assetID: asset.id))
            }
        }
        // Range sanity.
        if let lo = meta.binding.minValue, let hi = meta.binding.maxValue, hi <= lo {
            out.append(issue(.error, .invalidRange,
                             "Asset '\(asset.name)' range is empty or inverted (min ≥ max).",
                             assetID: asset.id))
        }
        if let lo = meta.binding.minValue, let hi = meta.binding.maxValue, let def = meta.binding.defaultValue,
           def < lo || def > hi {
            out.append(issue(.warning, .defaultOutOfRange,
                             "Asset '\(asset.name)' default is outside its range.", assetID: asset.id))
        }
        if let cc = meta.binding.midiCC, cc < 0 || cc > 127 {
            out.append(issue(.error, .midiCCOutOfRange,
                             "Asset '\(asset.name)' MIDI CC \(cc) is out of 0…127.", assetID: asset.id))
        }
        if !meta.binding.isContinuous, meta.binding.stepCount == nil {
            out.append(issue(.warning, .missingSteps,
                             "Asset '\(asset.name)' is stepped but no stepCount is set.", assetID: asset.id))
        }
        // Role ↔ function consistency.
        if (meta.role == .knobCap && meta.function != .rotaryControl)
            || (meta.role == .faderCap && meta.function != .linearControl)
            || (meta.role == .button && meta.function != .pressControl)
            || (meta.role == .toggleSwitch && meta.function != .toggleControl) {
            out.append(issue(.info, .roleFunctionMismatch,
                             "Asset '\(asset.name)': role \(meta.role.displayName) doesn't match function \(meta.function.rawValue).",
                             assetID: asset.id))
        }
        return out
    }

    /// Runs validation across every asset in a document.
    public static func validate(assets: [Asset]) -> [Issue] {
        assets.flatMap { validate($0) }.sorted { $0.severity > $1.severity }
    }

    private static func issue(_ severity: Issue.Severity, _ code: Issue.Code,
                              _ message: String, assetID: UUID) -> Issue {
        Issue(severity: severity, code: code, message: message, assetID: assetID)
    }
}
