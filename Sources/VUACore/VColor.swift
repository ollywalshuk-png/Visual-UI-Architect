import Foundation

/// sRGB color in the domain layer. Stays independent of SwiftUI/AppKit `Color`.
public struct VColor: Codable, Hashable, Sendable {
    public var red: Double      // 0...1
    public var green: Double    // 0...1
    public var blue: Double     // 0...1
    public var alpha: Double    // 0...1

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red.clamped01
        self.green = green.clamped01
        self.blue = blue.clamped01
        self.alpha = alpha.clamped01
    }

    public static let clear = VColor(red: 0, green: 0, blue: 0, alpha: 0)
    public static let white = VColor(red: 1, green: 1, blue: 1)
    public static let black = VColor(red: 0, green: 0, blue: 0)

    /// Hex string like `#RRGGBB` or `#RRGGBBAA`.
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let value = UInt64(s, radix: 16) else { return nil }
        switch s.count {
        case 6:
            self.init(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255)
        case 8:
            self.init(
                red: Double((value >> 24) & 0xFF) / 255,
                green: Double((value >> 16) & 0xFF) / 255,
                blue: Double((value >> 8) & 0xFF) / 255,
                alpha: Double(value & 0xFF) / 255)
        default:
            return nil
        }
    }

    public var hexString: String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// WCAG relative luminance (sRGB). Used by the accessibility engine.
    public var relativeLuminance: Double {
        func lin(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
    }
}

extension Double {
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}
