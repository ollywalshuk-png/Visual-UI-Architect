import Foundation

public struct DesignToken: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var kind: DesignTokenKind
    public var value: DesignTokenValue

    public init(id: UUID = UUID(), name: String, kind: DesignTokenKind, value: DesignTokenValue) {
        self.id = id
        self.name = name
        self.kind = kind
        self.value = value
    }

    public var swiftName: String {
        let allowed = name.map { $0.isLetter || $0.isNumber ? $0 : "_" }
        let raw = String(allowed).split(separator: "_").filter { !$0.isEmpty }
        let joined = raw.enumerated().map { index, part in
            index == 0 ? part.lowercased() : part.prefix(1).uppercased() + part.dropFirst()
        }.joined()
        return joined.isEmpty ? "token" : joined
    }
}

public enum DesignTokenKind: String, Codable, Hashable, Sendable, CaseIterable {
    case color, typography, spacing, cornerRadius, shadow, gradient, material
}

public enum DesignTokenValue: Codable, Hashable, Sendable {
    case color(VColor)
    case typography(size: Double, weight: LayerStyle.FontWeight?)
    case spacing(Double)
    case cornerRadius(Double)
    case shadow(ShadowSpec)
    case gradient(GradientSpec)
    case material(String)
}

public struct LayerTokenReferences: Codable, Hashable, Sendable {
    public var backgroundColor: UUID?
    public var foregroundColor: UUID?
    public var typography: UUID?
    public var spacing: UUID?
    public var cornerRadius: UUID?
    public var shadow: UUID?
    public var gradient: UUID?
    public var material: UUID?

    public init(backgroundColor: UUID? = nil,
                foregroundColor: UUID? = nil,
                typography: UUID? = nil,
                spacing: UUID? = nil,
                cornerRadius: UUID? = nil,
                shadow: UUID? = nil,
                gradient: UUID? = nil,
                material: UUID? = nil) {
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.typography = typography
        self.spacing = spacing
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.gradient = gradient
        self.material = material
    }

    public var isEmpty: Bool {
        [backgroundColor, foregroundColor, typography, spacing, cornerRadius, shadow, gradient, material]
            .allSatisfy { $0 == nil }
    }
}
