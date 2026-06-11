import Foundation
import VUACore

public enum VectorPathDiagnosticCode: String, Sendable {
    case invalidPath
    case emptyPath
    case unsupportedSVGCommand
    case pathOutsideCanvas
    case missingFillStroke
}

public struct VectorPathDiagnostic: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public var code: VectorPathDiagnosticCode
    public var message: String
    public var layerID: UUID?
}

public enum VectorDrawingEngine {
    public static func validate(layer: Layer, canvasSize: VSize) -> [VectorPathDiagnostic] {
        guard layer.kind == .vectorPath else { return [] }
        guard let path = layer.vectorPath else {
            return [VectorPathDiagnostic(code: .emptyPath,
                                         message: "\(layer.name) has no vector path metadata.",
                                         layerID: layer.id)]
        }
        var out: [VectorPathDiagnostic] = []
        if path.anchors.isEmpty {
            out.append(VectorPathDiagnostic(code: .emptyPath,
                                            message: "\(layer.name) vector path is empty.",
                                            layerID: layer.id))
        } else if path.anchors.count < 2 {
            out.append(VectorPathDiagnostic(code: .invalidPath,
                                            message: "\(layer.name) needs at least two anchor points.",
                                            layerID: layer.id))
        }
        if path.strokeColor == nil && path.fillColor == nil {
            out.append(VectorPathDiagnostic(code: .missingFillStroke,
                                            message: "\(layer.name) has no fill or stroke.",
                                            layerID: layer.id))
        }
        for command in path.unsupportedSVGCommands {
            out.append(VectorPathDiagnostic(code: .unsupportedSVGCommand,
                                            message: "\(layer.name) contains unsupported SVG command \(command).",
                                            layerID: layer.id))
        }
        let bounds = VRect(origin: .zero, size: canvasSize)
        for anchor in path.anchors {
            let p = VPoint(x: layer.frame.origin.x + anchor.point.x,
                           y: layer.frame.origin.y + anchor.point.y)
            if !bounds.contains(p) {
                out.append(VectorPathDiagnostic(code: .pathOutsideCanvas,
                                                message: "\(layer.name) vector path extends outside the canvas.",
                                                layerID: layer.id))
                break
            }
        }
        return out
    }

    public static func svgPathData(_ path: VectorPathSpec) -> String {
        guard let first = path.anchors.first else { return "" }
        var parts = ["M \(fmt(first.point.x)) \(fmt(first.point.y))"]
        for (previous, current) in zip(path.anchors, path.anchors.dropFirst()) {
            if let c1 = previous.handleOut, let c2 = current.handleIn {
                parts.append("C \(fmt(c1.x)) \(fmt(c1.y)) \(fmt(c2.x)) \(fmt(c2.y)) \(fmt(current.point.x)) \(fmt(current.point.y))")
            } else {
                parts.append("L \(fmt(current.point.x)) \(fmt(current.point.y))")
            }
        }
        if path.isClosed { parts.append("Z") }
        return parts.joined(separator: " ")
    }

    public static func exportSVG(layer: Layer) -> String? {
        guard let path = layer.vectorPath, !path.anchors.isEmpty else { return nil }
        let fill = path.fillColor.map { $0.hexString } ?? "none"
        let stroke = path.strokeColor.map { $0.hexString } ?? "none"
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(fmt(layer.frame.width))" height="\(fmt(layer.frame.height))" viewBox="0 0 \(fmt(layer.frame.width)) \(fmt(layer.frame.height))">
          <path d="\(svgPathData(path))" fill="\(fill)" stroke="\(stroke)" stroke-width="\(fmt(path.strokeWidth))"/>
        </svg>
        """
    }

    private static func fmt(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.2f", value)
    }
}
