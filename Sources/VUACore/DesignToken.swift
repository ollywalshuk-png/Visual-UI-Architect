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
    case color, typography, spacing, cornerRadius, border, shadow, elevation, opacity, gradient, material, glass
}

public enum DesignTokenValue: Codable, Hashable, Sendable {
    case color(VColor)
    case typography(size: Double, weight: LayerStyle.FontWeight?)
    case spacing(Double)
    case cornerRadius(Double)
    case border(width: Double, color: VColor)
    case shadow(ShadowSpec)
    case elevation(Double)
    case opacity(Double)
    case gradient(GradientSpec)
    case material(String)
    case glass(style: String, tint: VColor?)
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
    public var border: UUID?
    public var elevation: UUID?
    public var opacity: UUID?
    public var glass: UUID?

    public init(backgroundColor: UUID? = nil,
                foregroundColor: UUID? = nil,
                typography: UUID? = nil,
                spacing: UUID? = nil,
                cornerRadius: UUID? = nil,
                shadow: UUID? = nil,
                gradient: UUID? = nil,
                material: UUID? = nil,
                border: UUID? = nil,
                elevation: UUID? = nil,
                opacity: UUID? = nil,
                glass: UUID? = nil) {
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.typography = typography
        self.spacing = spacing
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.gradient = gradient
        self.material = material
        self.border = border
        self.elevation = elevation
        self.opacity = opacity
        self.glass = glass
    }

    public var isEmpty: Bool {
        [backgroundColor, foregroundColor, typography, spacing, cornerRadius, shadow, gradient, material, border, elevation, opacity, glass]
            .allSatisfy { $0 == nil }
    }
}

public struct DesignTheme: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var family: String
    public var tokens: [DesignToken]
    public var tags: [String]

    public init(id: String, name: String, family: String, tokens: [DesignToken], tags: [String] = []) {
        self.id = id
        self.name = name
        self.family = family
        self.tokens = tokens
        self.tags = tags
    }
}

public enum DesignThemeLibrary {
    public static let all: [DesignTheme] = [
        make(id: "apple.light", name: "Apple Light", family: "Apple", bg: "#F5F5F7", fg: "#1D1D1F", accent: "#007AFF", material: "regularMaterial", glass: "window"),
        make(id: "apple.dark", name: "Apple Dark", family: "Apple", bg: "#1C1C1E", fg: "#F5F5F7", accent: "#0A84FF", material: "regularMaterial", glass: "panel"),
        make(id: "apple.glass", name: "Apple Glass", family: "Apple", bg: "#E8EEF7", fg: "#111318", accent: "#5AC8FA", material: "ultraThinMaterial", glass: "floating"),
        make(id: "apple.vision", name: "Apple Vision", family: "Apple", bg: "#F2F4F8", fg: "#15171C", accent: "#64D2FF", material: "thinMaterial", glass: "window"),
        make(id: "modern.pro", name: "Modern Pro", family: "Modern", bg: "#171A20", fg: "#F2F2F7", accent: "#30D158", material: "regularMaterial", glass: "panel"),
        make(id: "modern.dark", name: "Modern Dark", family: "Modern", bg: "#101114", fg: "#EDEDF2", accent: "#BF5AF2", material: "thinMaterial", glass: "toolbar"),
        make(id: "studio.dark", name: "Studio Dark", family: "Studio", bg: "#15171A", fg: "#F4F1E8", accent: "#FF9F0A", material: "thickMaterial", glass: "sidebar"),
        make(id: "audio.workstation", name: "Audio Workstation", family: "Audio", bg: "#202124", fg: "#E7E2D6", accent: "#FFD60A", material: "regularMaterial", glass: "panel"),
        make(id: "electron.dark", name: "Electron Dark", family: "Web", bg: "#111827", fg: "#E5E7EB", accent: "#38BDF8", material: "regularMaterial", glass: "window"),
        make(id: "raycast.style", name: "Raycast-style", family: "Productivity", bg: "#151515", fg: "#FFFFFF", accent: "#FF6363", material: "thinMaterial", glass: "floating"),
        make(id: "linear.style", name: "Linear-style", family: "Productivity", bg: "#0F1014", fg: "#F7F8F8", accent: "#5E6AD2", material: "regularMaterial", glass: "panel"),
        make(id: "notion.style", name: "Notion-style", family: "Productivity", bg: "#FBFBFA", fg: "#2F3437", accent: "#2383E2", material: "regularMaterial", glass: "sidebar"),
        make(id: "daw.dark", name: "DAW Dark", family: "Audio", bg: "#191B1F", fg: "#E9E4D8", accent: "#FFCC00", material: "thickMaterial", glass: "toolbar"),
        make(id: "ableton.inspired", name: "Ableton-inspired", family: "Audio", bg: "#D9D5CA", fg: "#111111", accent: "#00A3FF", material: "regularMaterial", glass: "panel"),
        make(id: "logic.inspired", name: "Logic-inspired", family: "Audio", bg: "#20242A", fg: "#F2F7FF", accent: "#30D158", material: "ultraThinMaterial", glass: "floating")
    ]

    public static func theme(id: String) -> DesignTheme? { all.first { $0.id == id } }

    private static func make(id: String, name: String, family: String, bg: String, fg: String, accent: String, material: String, glass: String) -> DesignTheme {
        let background = VColor(hex: bg) ?? .black
        let foreground = VColor(hex: fg) ?? .white
        let accentColor = VColor(hex: accent) ?? .white
        return DesignTheme(id: id, name: name, family: family, tokens: [
            DesignToken(name: "\(name) Background", kind: .color, value: .color(background)),
            DesignToken(name: "\(name) Foreground", kind: .color, value: .color(foreground)),
            DesignToken(name: "\(name) Accent", kind: .color, value: .color(accentColor)),
            DesignToken(name: "\(name) Body", kind: .typography, value: .typography(size: 15, weight: .regular)),
            DesignToken(name: "\(name) Space 8", kind: .spacing, value: .spacing(8)),
            DesignToken(name: "\(name) Radius", kind: .cornerRadius, value: .cornerRadius(glass == "floating" ? 18 : 10)),
            DesignToken(name: "\(name) Border", kind: .border, value: .border(width: 1, color: accentColor)),
            DesignToken(name: "\(name) Shadow", kind: .shadow, value: .shadow(ShadowSpec(color: VColor(red: 0, green: 0, blue: 0, alpha: 0.28), radius: 10, x: 0, y: 4))),
            DesignToken(name: "\(name) Elevation", kind: .elevation, value: .elevation(2)),
            DesignToken(name: "\(name) Opacity", kind: .opacity, value: .opacity(0.94)),
            DesignToken(name: "\(name) Material", kind: .material, value: .material(material)),
            DesignToken(name: "\(name) Glass", kind: .glass, value: .glass(style: glass, tint: accentColor))
        ], tags: [family.lowercased(), glass, material])
    }
}
