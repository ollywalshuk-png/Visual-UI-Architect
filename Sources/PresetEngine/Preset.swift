import Foundation
import VUACore

/// A reusable layout preset — a named, categorised layer subtree the user can
/// drop into a document. Building returns a single root layer (usually a group)
/// positioned at the requested origin.
public struct Preset: Identifiable, Sendable {
    public enum Category: String, Sendable, CaseIterable {
        case appScreens = "App Screens"
        case panels = "Panels"
        case cards = "Cards"
        case navigation = "Navigation"
        case toolbars = "Toolbars"
        case forms = "Forms"
        case dashboards = "Dashboards"
        case pluginControls = "Plugin Controls"
        case mobile = "Mobile"
        case watch = "watchOS"
        case modals = "Modals"
    }

    public let id: String
    public let name: String
    public let category: Category
    /// Builds the preset rooted at `origin` (top-left).
    public let build: @Sendable (_ origin: VPoint) -> Layer

    public init(id: String, name: String, category: Category,
                build: @escaping @Sendable (_ origin: VPoint) -> Layer) {
        self.id = id
        self.name = name
        self.category = category
        self.build = build
    }
}

/// Helpers for building preset layer trees concisely.
public enum PresetBuild {
    public static func group(_ name: String, _ size: VSize, role: LayerRole = .panel,
                             at origin: VPoint, _ children: [Layer]) -> Layer {
        Layer(name: name, kind: .group,
              frame: VRect(x: origin.x, y: origin.y, width: size.width, height: size.height),
              role: role, children: children)
    }

    public static func panel(_ name: String, _ rect: VRect, color: String = "#1C1C1E",
                             radius: Double = 14) -> Layer {
        Layer(name: name, kind: .panel, frame: rect,
              style: LayerStyle(backgroundColor: VColor(hex: color), cornerRadius: radius),
              role: .panel)
    }

    public static func card(_ name: String, _ rect: VRect, color: String = "#2C2C2E") -> Layer {
        Layer(name: name, kind: .shape(.card), frame: rect,
              style: LayerStyle(backgroundColor: VColor(hex: color), cornerRadius: 12,
                                shadow: ShadowSpec()),
              role: .panel)
    }

    public static func label(_ text: String, _ rect: VRect, size: Double = 15,
                             weight: LayerStyle.FontWeight = .regular, color: String = "#FFFFFF") -> Layer {
        Layer(name: text, kind: .label, frame: rect,
              style: LayerStyle(foregroundColor: VColor(hex: color), fontSize: size, fontWeight: weight),
              text: text, role: .label)
    }

    public static func button(_ text: String, _ rect: VRect, color: String = "#0A84FF") -> Layer {
        Layer(name: text, kind: .button, frame: rect,
              style: LayerStyle(backgroundColor: VColor(hex: color), foregroundColor: .white,
                                cornerRadius: 8, fontSize: 15, fontWeight: .semibold),
              text: text, role: .control)
    }

    public static func toggle(_ text: String, _ rect: VRect) -> Layer {
        Layer(name: text, kind: .toggle, frame: rect,
              style: LayerStyle(foregroundColor: .white, fontSize: 15), text: text, role: .control)
    }

    public static func knob(_ text: String, _ rect: VRect, param: String) -> Layer {
        Layer(name: text, kind: .knob, frame: rect,
              style: LayerStyle(backgroundColor: VColor(hex: "#3A3A3C"), cornerRadius: rect.width / 2),
              control: ControlMetadata(parameterID: param, displayName: text),
              role: .control)
    }

    public static func fader(_ text: String, _ rect: VRect, param: String) -> Layer {
        Layer(name: text, kind: .fader, frame: rect,
              style: LayerStyle(backgroundColor: VColor(hex: "#3A3A3C"), cornerRadius: 6),
              control: ControlMetadata(parameterID: param, displayName: text,
                                       minValue: -60, maxValue: 6, defaultValue: 0, unit: .decibels),
              role: .control)
    }

    public static func divider(_ rect: VRect) -> Layer {
        Layer(name: "Divider", kind: .shape(.divider), frame: rect,
              style: LayerStyle(backgroundColor: VColor(hex: "#3A3A3C")), role: .decoration)
    }

    public static func gradientHeader(_ rect: VRect, from: String, to: String) -> Layer {
        Layer(name: "Gradient Header", kind: .gradient, frame: rect,
              style: LayerStyle(gradient: GradientSpec(
                stops: [GradientStop(color: VColor(hex: from) ?? .black, location: 0),
                        GradientStop(color: VColor(hex: to) ?? .white, location: 1)])),
              role: .background)
    }
}
