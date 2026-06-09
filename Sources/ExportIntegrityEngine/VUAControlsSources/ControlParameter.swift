import SwiftUI

/// Self-contained value-mapping for a plugin control. Kept independent of the
/// editor's domain model so this library can ship on its own.
public struct ControlRange: Sendable, Hashable {
    public var min: Double
    public var max: Double

    public init(_ min: Double = 0, _ max: Double = 1) {
        self.min = min
        self.max = max
    }

    public var span: Double { Swift.max(0.000001, max - min) }

    /// Maps a raw value to 0...1.
    public func normalize(_ value: Double) -> Double {
        Swift.min(1, Swift.max(0, (value - min) / span))
    }

    /// Maps a 0...1 position back to a raw value.
    public func denormalize(_ position: Double) -> Double {
        min + Swift.min(1, Swift.max(0, position)) * span
    }

    public func clamp(_ value: Double) -> Double {
        Swift.min(max, Swift.max(min, value))
    }
}

/// Shared visual theme for the control library.
public struct ControlTheme: Sendable {
    public var accent: Color
    public var track: Color
    public var indicator: Color

    public init(accent: Color = Color(.sRGB, red: 0.039, green: 0.518, blue: 1, opacity: 1),
                track: Color = Color.black.opacity(0.4),
                indicator: Color = .white) {
        self.accent = accent
        self.track = track
        self.indicator = indicator
    }

    public static let `default` = ControlTheme()
}

public extension EnvironmentValues {
    var controlTheme: ControlTheme {
        get { self[ControlThemeKey.self] }
        set { self[ControlThemeKey.self] = newValue }
    }
}

private struct ControlThemeKey: EnvironmentKey {
    static let defaultValue = ControlTheme.default
}
