import Foundation
import AppKit
import VUACore

public enum RasterPaintDiagnosticCode: String, Sendable {
    case noSelectedImageLayer
    case unsupportedImageFormat
    case noStrokes
    case exportPNGFailed
    case paintedAssetMissing
}

public struct RasterPaintDiagnostic: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public var code: RasterPaintDiagnosticCode
    public var message: String
    public var layerID: UUID?
}

public struct RasterPaintExportResult: Sendable {
    public var asset: Asset
    public var pngData: Data
    public var originalAssetID: UUID?
}

public enum RasterDrawingEngine {
    public static func validatePaintLayer(_ layer: Layer, asset: Asset?) -> [RasterPaintDiagnostic] {
        guard layer.kind == .image || layer.kind == .background else {
            return [RasterPaintDiagnostic(code: .noSelectedImageLayer,
                                          message: "Select an image or background layer before painting.",
                                          layerID: layer.id)]
        }
        guard let paint = layer.rasterPaint else {
            return [RasterPaintDiagnostic(code: .noStrokes,
                                          message: "\(layer.name) has no paint layer.",
                                          layerID: layer.id)]
        }
        guard paint.hasDrawableStrokes else {
            return [RasterPaintDiagnostic(code: .noStrokes,
                                          message: "\(layer.name) paint layer has no drawable strokes.",
                                          layerID: layer.id)]
        }
        if let asset, asset.format != .png && asset.format != .jpeg {
            return [RasterPaintDiagnostic(code: .unsupportedImageFormat,
                                          message: "\(asset.name) is not a raster image format.",
                                          layerID: layer.id)]
        }
        return []
    }

    public static func exportPaintedPNG(layer: Layer, baseAsset: Asset?, name: String? = nil) -> RasterPaintExportResult? {
        guard let paint = layer.rasterPaint, paint.hasDrawableStrokes else { return nil }
        let size = NSSize(width: max(1, layer.frame.width), height: max(1, layer.frame.height))
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        for stroke in paint.strokes where stroke.isDrawable {
            draw(stroke)
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        let assetName = name ?? "\(layer.name.replacingOccurrences(of: " ", with: "_"))_Paint"
        let asset = Asset(
            name: assetName,
            path: "\(assetName).png",
            format: .png,
            intrinsicSize: VSize(width: size.width, height: size.height),
            tags: ["paint", "raster", "generated"])
        return RasterPaintExportResult(asset: asset, pngData: data, originalAssetID: baseAsset?.id)
    }

    private static func draw(_ stroke: RasterPaintStroke) {
        let path = NSBezierPath()
        guard let first = stroke.points.first else { return }
        path.move(to: NSPoint(x: first.x, y: first.y))
        for point in stroke.points.dropFirst() {
            path.line(to: NSPoint(x: point.x, y: point.y))
        }
        path.lineWidth = stroke.brush.size
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        let color = stroke.brush.tool == .eraser
            ? NSColor.clear
            : NSColor(calibratedRed: stroke.brush.color.red,
                      green: stroke.brush.color.green,
                      blue: stroke.brush.color.blue,
                      alpha: stroke.brush.color.alpha * stroke.brush.opacity)
        color.setStroke()
        path.stroke()
    }
}
