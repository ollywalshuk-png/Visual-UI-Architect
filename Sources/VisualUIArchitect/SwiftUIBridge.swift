import SwiftUI
import VUACore

/// Conversions between the platform-independent domain types and SwiftUI/CG.
extension VColor {
    var swiftUI: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

extension GradientSpec {
    /// A SwiftUI gradient `ShapeStyle` mirroring the code generator's output.
    var swiftUIFill: AnyShapeStyle {
        let gradient = Gradient(stops: stops.map {
            Gradient.Stop(color: $0.color.swiftUI, location: $0.location)
        })
        switch kind {
        case .linear:
            return AnyShapeStyle(LinearGradient(
                gradient: gradient,
                startPoint: UnitPoint(x: startPoint.x, y: startPoint.y),
                endPoint: UnitPoint(x: endPoint.x, y: endPoint.y)))
        case .radial:
            return AnyShapeStyle(RadialGradient(gradient: gradient, center: .center, startRadius: 0, endRadius: 200))
        case .angular:
            return AnyShapeStyle(AngularGradient(gradient: gradient, center: .center))
        }
    }
}

/// A SwiftUI `Shape` rendering a regular polygon or star from a `PolygonSpec`,
/// matching the geometry the code generator emits.
struct PolygonShape: Shape {
    let spec: PolygonSpec

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX, cy = rect.midY
        let rx = rect.width / 2, ry = rect.height / 2
        let n = max(3, spec.sides)
        let rot = spec.rotationDegrees * .pi / 180
        var path = Path()
        var points: [CGPoint] = []
        if let inner = spec.starInnerRatio {
            for i in 0..<(n * 2) {
                let angle = -Double.pi / 2 + rot + Double(i) * .pi / Double(n)
                let r = i % 2 == 0 ? 1.0 : inner
                points.append(CGPoint(x: cx + CGFloat(cos(angle)) * rx * r, y: cy + CGFloat(sin(angle)) * ry * r))
            }
        } else {
            for i in 0..<n {
                let angle = -Double.pi / 2 + rot + Double(i) * 2 * .pi / Double(n)
                points.append(CGPoint(x: cx + CGFloat(cos(angle)) * rx, y: cy + CGFloat(sin(angle)) * ry))
            }
        }
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }
}

extension Color {
    /// Best-effort conversion back to a domain color (used by the inspector).
    var vColor: VColor {
        #if canImport(AppKit)
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return VColor(red: Double(ns.redComponent), green: Double(ns.greenComponent),
                      blue: Double(ns.blueComponent), alpha: Double(ns.alphaComponent))
        #else
        return .white
        #endif
    }
}

extension VRect {
    var cg: CGRect { CGRect(x: origin.x, y: origin.y, width: size.width, height: size.height) }
}

extension VPoint {
    var cg: CGPoint { CGPoint(x: x, y: y) }
}

extension VSize {
    var cg: CGSize { CGSize(width: width, height: height) }
}

extension LayerStyle.FontWeight {
    var swiftUI: Font.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }
}

extension LineCapStyle {
    var swiftUI: CGLineCap {
        switch self {
        case .butt: return .butt
        case .round: return .round
        case .square: return .square
        }
    }
}

extension LineJoinStyle {
    var swiftUI: CGLineJoin {
        switch self {
        case .miter: return .miter
        case .round: return .round
        case .bevel: return .bevel
        }
    }
}
