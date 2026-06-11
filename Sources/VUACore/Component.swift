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
    /// Named variants override the master for specific visual states/usages.
    /// The base `master` remains the inherited default.
    public var variants: [ComponentVariant]

    public init(id: UUID = UUID(), name: String, category: String? = nil,
                master: Layer, version: Int = 1, variants: [ComponentVariant] = []) {
        self.id = id
        self.name = name
        self.category = category
        self.master = master
        self.version = version
        self.variants = variants
    }

    enum CodingKeys: String, CodingKey { case id, name, category, master, version, variants }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        master = try c.decode(Layer.self, forKey: .master)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        variants = try c.decodeIfPresent([ComponentVariant].self, forKey: .variants) ?? []
    }

    /// A SwiftUI-safe type name derived from the component name (e.g. "Card" →
    /// "CardComponentView").
    public var generatedTypeName: String {
        let allowed = name.filter { $0.isLetter || $0.isNumber || $0 == "_" }
        let stem = allowed.isEmpty ? "Component" : allowed
        let head = stem.first.map { String($0).uppercased() } ?? "C"
        return head + stem.dropFirst() + "ComponentView"
    }

    public func variant(id: UUID?) -> ComponentVariant? {
        guard let id else { return nil }
        return variants.first { $0.id == id }
    }
}

public struct ComponentVariant: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var master: Layer

    public init(id: UUID = UUID(), name: String, master: Layer) {
        self.id = id
        self.name = name
        self.master = master
    }
}

public struct ComponentOverride: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var property: String
    public var valueDescription: String

    public init(id: UUID = UUID(), property: String, valueDescription: String) {
        self.id = id
        self.property = property
        self.valueDescription = valueDescription
    }
}
