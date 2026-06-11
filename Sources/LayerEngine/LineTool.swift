import Foundation
import VUACore

public enum LineToolDiagnosticCode: String, Sendable {
    case zeroLength
    case invisibleStroke
    case invalidArrow
    case unsupportedConnector
    case lineOutsideCanvas
}

public struct LineToolDiagnostic: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public var code: LineToolDiagnosticCode
    public var message: String
    public var layerID: UUID
}

public enum LineTool {
    public static func makeDefault(width: Double = 160, height: Double = 24) -> LineSpec {
        LineSpec(start: VPoint(x: 0, y: height / 2),
                 end: VPoint(x: width, y: height / 2),
                 lineCap: .round,
                 lineJoin: .round,
                 connectorMode: .straight)
    }

    public static func constrainedEnd(start: VPoint, proposed: VPoint) -> VPoint {
        let dx = proposed.x - start.x
        let dy = proposed.y - start.y
        guard dx != 0 || dy != 0 else { return proposed }
        let angle = atan2(dy, dx)
        let step = Double.pi / 4
        let snapped = (angle / step).rounded() * step
        let length = hypot(dx, dy)
        return VPoint(x: start.x + cos(snapped) * length,
                      y: start.y + sin(snapped) * length)
    }

    public static func pathCommands(for line: LineSpec, in frame: VRect) -> [String] {
        switch line.effectiveConnector {
        case .straight:
            return ["move \(line.start.x),\(line.start.y)", "line \(line.end.x),\(line.end.y)"]
        case .curved:
            let c1 = line.controlPoint1 ?? VPoint(x: frame.width * 0.33, y: line.start.y)
            let c2 = line.controlPoint2 ?? VPoint(x: frame.width * 0.66, y: line.end.y)
            return ["move \(line.start.x),\(line.start.y)", "curve \(c1.x),\(c1.y) \(c2.x),\(c2.y) \(line.end.x),\(line.end.y)"]
        case .elbow:
            let mid = VPoint(x: line.end.x, y: line.start.y)
            return ["move \(line.start.x),\(line.start.y)", "line \(mid.x),\(mid.y)", "line \(line.end.x),\(line.end.y)"]
        }
    }

    public static func validate(_ layer: Layer, canvasSize: VSize) -> [LineToolDiagnostic] {
        guard case .line = layer.kind else { return [] }
        let line = layer.line ?? makeDefault(width: layer.frame.width, height: layer.frame.height)
        var out: [LineToolDiagnostic] = []
        if line.length <= 0.5 {
            out.append(LineToolDiagnostic(code: .zeroLength,
                                          message: "\(layer.name) has zero-length line geometry.",
                                          layerID: layer.id))
        }
        let strokeWidth = layer.style.borderWidth
        let strokeAlpha = layer.style.borderColor?.alpha ?? layer.style.foregroundColor?.alpha ?? 1
        if strokeWidth <= 0 || strokeAlpha <= 0.001 || layer.style.opacity <= 0.001 {
            out.append(LineToolDiagnostic(code: .invisibleStroke,
                                          message: "\(layer.name) has an invisible stroke.",
                                          layerID: layer.id))
        }
        if line.arrowStart && line.arrowEnd && line.length < 12 {
            out.append(LineToolDiagnostic(code: .invalidArrow,
                                          message: "\(layer.name) is too short for arrows at both ends.",
                                          layerID: layer.id))
        }
        if line.effectiveConnector == .curved && (line.controlPoint1 == nil || line.controlPoint2 == nil) {
            out.append(LineToolDiagnostic(code: .unsupportedConnector,
                                          message: "\(layer.name) curved connector is using generated handles.",
                                          layerID: layer.id))
        }
        let bounds = VRect(origin: .zero, size: canvasSize)
        let absoluteStart = VPoint(x: layer.frame.origin.x + line.start.x, y: layer.frame.origin.y + line.start.y)
        let absoluteEnd = VPoint(x: layer.frame.origin.x + line.end.x, y: layer.frame.origin.y + line.end.y)
        if !bounds.contains(absoluteStart) || !bounds.contains(absoluteEnd) {
            out.append(LineToolDiagnostic(code: .lineOutsideCanvas,
                                          message: "\(layer.name) starts or ends outside the canvas.",
                                          layerID: layer.id))
        }
        return out
    }
}
