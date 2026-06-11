import Foundation

/// The serialisable design document: the layer tree plus its supporting
/// resources. This is the single source of truth the engines operate on.
public struct Document: Codable, Hashable, Sendable {
    public var name: String
    /// Root-level layers (z-ordered back-to-front).
    public var roots: [Layer]
    public var assets: [Asset]
    /// The device the canvas is currently authored against.
    public var activeDevice: DeviceProfile
    public var activeOrientation: DeviceProfile.Orientation
    /// Code-generation target for this document.
    public var codeGenTarget: CodeGenTarget
    /// Reusable component library (Phase 15). Decodes to [] for older documents.
    public var components: [Component]
    /// Reusable design tokens (Phase 28). Layers can reference these while
    /// retaining concrete fallback values for older exports/imports.
    public var designTokens: [DesignToken]
    /// Schema version for forward-compatible migration.
    public var schemaVersion: Int

    public static let currentSchemaVersion = 1

    public init(
        name: String = "Untitled",
        roots: [Layer] = [],
        assets: [Asset] = [],
        activeDevice: DeviceProfile = .mac,
        activeOrientation: DeviceProfile.Orientation = .portrait,
        codeGenTarget: CodeGenTarget = .swiftUI,
        components: [Component] = [],
        designTokens: [DesignToken] = [],
        schemaVersion: Int = Document.currentSchemaVersion
    ) {
        self.name = name
        self.roots = roots
        self.assets = assets
        self.activeDevice = activeDevice
        self.activeOrientation = activeOrientation
        self.codeGenTarget = codeGenTarget
        self.components = components
        self.designTokens = designTokens
        self.schemaVersion = schemaVersion
    }

    private enum CodingKeys: String, CodingKey {
        case name, roots, assets, activeDevice, activeOrientation, codeGenTarget, components, designTokens, schemaVersion
    }

    /// Custom decoder so documents saved before Phase 15 (no `components` key)
    /// still load — `components` defaults to empty.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        roots = try c.decode([Layer].self, forKey: .roots)
        assets = try c.decode([Asset].self, forKey: .assets)
        activeDevice = try c.decode(DeviceProfile.self, forKey: .activeDevice)
        activeOrientation = try c.decode(DeviceProfile.Orientation.self, forKey: .activeOrientation)
        codeGenTarget = try c.decode(CodeGenTarget.self, forKey: .codeGenTarget)
        components = try c.decodeIfPresent([Component].self, forKey: .components) ?? []
        designTokens = try c.decodeIfPresent([DesignToken].self, forKey: .designTokens) ?? []
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
    }

    public var canvasSize: VSize { activeDevice.size(for: activeOrientation) }

    public func asset(id: UUID) -> Asset? { assets.first { $0.id == id } }
    public func component(id: UUID) -> Component? { components.first { $0.id == id } }
    public func designToken(id: UUID) -> DesignToken? { designTokens.first { $0.id == id } }
}

/// Supported code-generation targets. SwiftUI is implemented; the others are
/// declared so the architecture and UI account for them from day one.
public enum CodeGenTarget: String, Codable, Hashable, Sendable, CaseIterable {
    case swiftUI
    case uiKit
    case appKit
    // Reserved for expansion.
    case react
    case flutter
    case jetpackCompose

    public var displayName: String {
        switch self {
        case .swiftUI: return "SwiftUI"
        case .uiKit: return "UIKit"
        case .appKit: return "AppKit"
        case .react: return "React"
        case .flutter: return "Flutter"
        case .jetpackCompose: return "Jetpack Compose"
        }
    }

    public var isImplemented: Bool { self == .swiftUI }
}

// MARK: - Read-only tree traversal

public extension Layer {
    /// Depth-first pre-order traversal including the receiver.
    func flattened() -> [Layer] {
        var out: [Layer] = [self]
        for child in children { out.append(contentsOf: child.flattened()) }
        return out
    }

    /// Finds a descendant (or self) by id.
    func first(where id: UUID) -> Layer? {
        if self.id == id { return self }
        for child in children {
            if let found = child.first(where: id) { return found }
        }
        return nil
    }
}

public extension Document {
    var allLayers: [Layer] { roots.flatMap { $0.flattened() } }

    func layer(id: UUID) -> Layer? {
        for root in roots {
            if let found = root.first(where: id) { return found }
        }
        return nil
    }
}
