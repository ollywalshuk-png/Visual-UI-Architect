import Foundation

/// A reusable component definition (a "master"). Instances reference it by id;
/// editing the master and re-syncing updates every instance. Stored in the
/// document's component library so it persists in the `.vuaproj` bundle.
public struct Component: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var category: String?
    /// The master content laid out in component-local space. Children are the
    /// component's contents; the master frame defines its natural size.
    public var master: Layer
    /// Bumped each time the master is edited — instances compare to re-sync.
    public var version: Int

    public init(id: UUID = UUID(), name: String, category: String? = nil,
                master: Layer, version: Int = 1) {
        self.id = id
        self.name = name
        self.category = category
        self.master = master
        self.version = version
    }

    /// A SwiftUI-safe type name derived from the component name (e.g. "Card" →
    /// "CardComponentView").
    public var generatedTypeName: String {
        let allowed = name.filter { $0.isLetter || $0.isNumber || $0 == "_" }
        let stem = allowed.isEmpty ? "Component" : allowed
        let head = stem.first.map { String($0).uppercased() } ?? "C"
        return head + stem.dropFirst() + "ComponentView"
    }
}
