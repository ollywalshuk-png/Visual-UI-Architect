import Foundation
import VUACore

public struct ValidationIssue: Identifiable, Hashable, Sendable {
    public enum Severity: Int, Comparable, Sendable {
        case info, warning, error
        public static func < (l: Severity, r: Severity) -> Bool { l.rawValue < r.rawValue }

        public var label: String {
            switch self {
            case .info: return "Info"
            case .warning: return "Warning"
            case .error: return "Error"
            }
        }
    }

    public enum Category: String, Sendable {
        case contrast = "Contrast"
        case touchTarget = "Touch Target"
        case overlap = "Overlap"
        case clipping = "Clipping"
        case accessibility = "Accessibility"
        case layout = "Layout"
        case structure = "Structure"
        case asset = "Asset"
    }

    public let id: UUID
    public var severity: Severity
    public var category: Category
    public var message: String
    public var recommendation: String?
    /// Layers implicated, for selecting/highlighting in the UI.
    public var layerIDs: [UUID]

    public init(
        id: UUID = UUID(),
        severity: Severity,
        category: Category,
        message: String,
        recommendation: String? = nil,
        layerIDs: [UUID] = []
    ) {
        self.id = id
        self.severity = severity
        self.category = category
        self.message = message
        self.recommendation = recommendation
        self.layerIDs = layerIDs
    }
}

public struct ValidationReport: Sendable {
    public var issues: [ValidationIssue]
    public init(issues: [ValidationIssue]) { self.issues = issues }

    public var hasErrors: Bool { issues.contains { $0.severity == .error } }
    public var errorCount: Int { issues.filter { $0.severity == .error }.count }
    public var warningCount: Int { issues.filter { $0.severity == .warning }.count }
}
