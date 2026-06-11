import Foundation

/// Vector shape primitives a shape layer can render. Each maps to a real
/// SwiftUI shape or `Path` in generated code.
public enum ShapeKind: String, Codable, Hashable, Sendable, CaseIterable {
    case rectangle
    case roundedRectangle
    case ellipse
    case capsule
    case star
    case divider
    case card        // rounded panel with subtle styling
    case glassPanel  // translucent material panel
    case callout     // rounded rect with a pointer

    public var displayName: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .roundedRectangle: return "Rounded Rectangle"
        case .ellipse: return "Ellipse"
        case .capsule: return "Capsule"
        case .star: return "Star"
        case .divider: return "Divider"
        case .card: return "Card"
        case .glassPanel: return "Glass Panel"
        case .callout: return "Callout"
        }
    }
}

/// Semantic role of a layer — informs validation, presets, and future
/// export targets. Purely organisational; does not change rendering.
public enum LayerRole: String, Codable, Hashable, Sendable, CaseIterable {
    case background, panel, decoration, control, label, input
    case navigation, dataVisualisation, mask, guide
    case exportOnly   // present in generated code, hidden in editor
    case editorOnly   // editor scaffolding, omitted from generated code

    public var displayName: String {
        switch self {
        case .dataVisualisation: return "Data Visualisation"
        case .exportOnly: return "Export Only"
        case .editorOnly: return "Editor Only"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

/// A single gradient colour stop.
public struct GradientStop: Codable, Hashable, Sendable {
    public var color: VColor
    public var location: Double   // 0...1
    public init(color: VColor, location: Double) {
        self.color = color
        self.location = location.clamped01
    }
}

/// A gradient fill spec — maps to `LinearGradient`/`RadialGradient`/`AngularGradient`.
public struct GradientSpec: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case linear, radial, angular
    }
    public var kind: Kind
    public var stops: [GradientStop]
    /// Unit-space start/end points (0...1) used by linear/angular gradients.
    public var startPoint: VPoint
    public var endPoint: VPoint

    public init(kind: Kind = .linear,
                stops: [GradientStop] = [GradientStop(color: .black, location: 0),
                                         GradientStop(color: .white, location: 1)],
                startPoint: VPoint = VPoint(x: 0.5, y: 0),
                endPoint: VPoint = VPoint(x: 0.5, y: 1)) {
        self.kind = kind
        self.stops = stops
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    /// A top-to-bottom fade from `color` (opaque) to transparent.
    public static func fade(_ color: VColor = .black) -> GradientSpec {
        GradientSpec(stops: [GradientStop(color: color, location: 0),
                             GradientStop(color: VColor(red: color.red, green: color.green, blue: color.blue, alpha: 0), location: 1)])
    }
}

/// Drop shadow spec for a layer.
public struct ShadowSpec: Codable, Hashable, Sendable {
    public var color: VColor
    public var radius: Double
    public var x: Double
    public var y: Double
    public init(color: VColor = VColor(red: 0, green: 0, blue: 0, alpha: 0.33),
                radius: Double = 6, x: Double = 0, y: Double = 2) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }
}

/// A straight line / arrow / connector. Points are in the layer's local frame
/// space (0,0 = top-left of the frame), so the line moves/resizes with it.
public enum LineCapStyle: String, Codable, Hashable, Sendable, CaseIterable {
    case butt, round, square
}

public enum LineJoinStyle: String, Codable, Hashable, Sendable, CaseIterable {
    case miter, round, bevel
}

public enum LineConnectorMode: String, Codable, Hashable, Sendable, CaseIterable {
    case straight, curved, elbow
}

public enum LineSnapMode: String, Codable, Hashable, Sendable, CaseIterable {
    case none, layerEdge, layerCenter
}

public struct LineSpec: Codable, Hashable, Sendable {
    public var start: VPoint
    public var end: VPoint
    public var dashed: Bool
    public var arrowStart: Bool
    public var arrowEnd: Bool
    public var dotted: Bool?
    public var lineCap: LineCapStyle?
    public var lineJoin: LineJoinStyle?
    public var dividerMode: Bool?
    public var connectorMode: LineConnectorMode?
    public var snapMode: LineSnapMode?
    public var controlPoint1: VPoint?
    public var controlPoint2: VPoint?

    public init(start: VPoint, end: VPoint, dashed: Bool = false,
                arrowStart: Bool = false, arrowEnd: Bool = false,
                dotted: Bool = false, lineCap: LineCapStyle = .round,
                lineJoin: LineJoinStyle = .round, dividerMode: Bool = false,
                connectorMode: LineConnectorMode = .straight,
                snapMode: LineSnapMode = .none,
                controlPoint1: VPoint? = nil, controlPoint2: VPoint? = nil) {
        self.start = start
        self.end = end
        self.dashed = dashed
        self.arrowStart = arrowStart
        self.arrowEnd = arrowEnd
        self.dotted = dotted
        self.lineCap = lineCap
        self.lineJoin = lineJoin
        self.dividerMode = dividerMode
        self.connectorMode = connectorMode
        self.snapMode = snapMode
        self.controlPoint1 = controlPoint1
        self.controlPoint2 = controlPoint2
    }

    public var effectiveCap: LineCapStyle { lineCap ?? .round }
    public var effectiveJoin: LineJoinStyle { lineJoin ?? .round }
    public var effectiveConnector: LineConnectorMode { connectorMode ?? .straight }
    public var effectiveSnap: LineSnapMode { snapMode ?? .none }
    public var isDotted: Bool { dotted ?? false }
    public var isDivider: Bool { dividerMode ?? false }

    public var length: Double {
        hypot(end.x - start.x, end.y - start.y)
    }
}

/// Regular polygon / star spec.
public struct PolygonSpec: Codable, Hashable, Sendable {
    public var sides: Int             // >= 3
    public var rotationDegrees: Double
    /// nil → regular polygon; 0...1 → star with this inner-radius ratio.
    public var starInnerRatio: Double?
    public init(sides: Int = 6, rotationDegrees: Double = 0, starInnerRatio: Double? = nil) {
        self.sides = Swift.max(3, sides)
        self.rotationDegrees = rotationDegrees
        self.starInnerRatio = starInnerRatio
    }
    public var isValid: Bool { sides >= 3 && (starInnerRatio.map { $0 > 0 && $0 < 1 } ?? true) }
}

/// Masking metadata applied to a layer (and its children when it's a group).
public struct MaskSpec: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case shape   // clip to a ShapeKind
        case image   // alpha from an image asset
        case alpha   // alpha from the masking layer's own rendering
    }
    public var kind: Kind
    /// Shape used when `kind == .shape`.
    public var shape: ShapeKind
    public var invert: Bool
    public var feather: Double   // metadata; blur radius applied to the mask
    public init(kind: Kind = .shape, shape: ShapeKind = .roundedRectangle,
                invert: Bool = false, feather: Double = 0) {
        self.kind = kind
        self.shape = shape
        self.invert = invert
        self.feather = feather
    }
}

/// Asset/image transform metadata. This complements `LayerStyle`, which already
/// owns rotation, opacity, shadow, blur, border, stroke, and corner radius.
public enum LayerBlendMode: String, Codable, Hashable, Sendable, CaseIterable {
    case normal, multiply, screen, overlay, darken, lighten
}

public struct CropSpec: Codable, Hashable, Sendable {
    /// Unit-space crop rectangle in the asset's own bounds.
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double = 0, y: Double = 0, width: Double = 1, height: Double = 1) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var isValidUnitRect: Bool {
        x >= 0 && y >= 0 && width > 0 && height > 0 && x + width <= 1 && y + height <= 1
    }

    public var isIdentity: Bool {
        x == 0 && y == 0 && width == 1 && height == 1
    }
}

public struct AssetTransformSpec: Codable, Hashable, Sendable {
    public var scaleX: Double
    public var scaleY: Double
    public var flipHorizontal: Bool
    public var flipVertical: Bool
    public var crop: CropSpec?
    public var blendMode: LayerBlendMode
    /// Phase 23 hook for later texture/material work. It is metadata-only until
    /// Phase 26 adds material rendering.
    public var textureOverlayID: String?

    public init(scaleX: Double = 1, scaleY: Double = 1,
                flipHorizontal: Bool = false, flipVertical: Bool = false,
                crop: CropSpec? = nil, blendMode: LayerBlendMode = .normal,
                textureOverlayID: String? = nil) {
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.crop = crop
        self.blendMode = blendMode
        self.textureOverlayID = textureOverlayID
    }

    public var effectiveScaleX: Double { scaleX * (flipHorizontal ? -1 : 1) }
    public var effectiveScaleY: Double { scaleY * (flipVertical ? -1 : 1) }
    public var isIdentity: Bool {
        scaleX == 1 && scaleY == 1 && !flipHorizontal && !flipVertical &&
        (crop?.isIdentity ?? true) && blendMode == .normal && textureOverlayID == nil
    }
}

public enum RasterPaintTool: String, Codable, Hashable, Sendable, CaseIterable {
    case brush, pencil, eraser
}

public struct RasterBrushSpec: Codable, Hashable, Sendable {
    public var tool: RasterPaintTool
    public var size: Double
    public var opacity: Double
    public var hardness: Double
    public var color: VColor

    public init(tool: RasterPaintTool = .brush, size: Double = 12,
                opacity: Double = 1, hardness: Double = 0.75,
                color: VColor = .black) {
        self.tool = tool
        self.size = size
        self.opacity = opacity
        self.hardness = hardness
        self.color = color
    }
}

public struct RasterPaintStroke: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var brush: RasterBrushSpec
    public var points: [VPoint]

    public init(id: UUID = UUID(), brush: RasterBrushSpec = RasterBrushSpec(), points: [VPoint]) {
        self.id = id
        self.brush = brush
        self.points = points
    }

    public var isDrawable: Bool { points.count >= 2 && brush.size > 0 && brush.opacity > 0 }
}

/// Non-destructive raster drawing metadata. Strokes sit over an image layer and
/// can be flattened/exported as a new PNG asset without overwriting the source.
public struct RasterPaintSpec: Codable, Hashable, Sendable {
    public var isPaintModeEnabled: Bool
    public var activeBrush: RasterBrushSpec
    public var strokes: [RasterPaintStroke]
    public var exportedAssetID: UUID?
    public var exportedAssetName: String?
    public var preservesOriginalAsset: Bool

    public init(isPaintModeEnabled: Bool = false,
                activeBrush: RasterBrushSpec = RasterBrushSpec(),
                strokes: [RasterPaintStroke] = [],
                exportedAssetID: UUID? = nil,
                exportedAssetName: String? = nil,
                preservesOriginalAsset: Bool = true) {
        self.isPaintModeEnabled = isPaintModeEnabled
        self.activeBrush = activeBrush
        self.strokes = strokes
        self.exportedAssetID = exportedAssetID
        self.exportedAssetName = exportedAssetName
        self.preservesOriginalAsset = preservesOriginalAsset
    }

    public var hasDrawableStrokes: Bool { strokes.contains { $0.isDrawable } }
}

public struct VectorAnchorPoint: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var point: VPoint
    public var handleIn: VPoint?
    public var handleOut: VPoint?

    public init(id: UUID = UUID(), point: VPoint, handleIn: VPoint? = nil, handleOut: VPoint? = nil) {
        self.id = id
        self.point = point
        self.handleIn = handleIn
        self.handleOut = handleOut
    }
}

public struct VectorPathSpec: Codable, Hashable, Sendable {
    public var anchors: [VectorAnchorPoint]
    public var isClosed: Bool
    public var strokeColor: VColor?
    public var strokeWidth: Double
    public var fillColor: VColor?
    /// Unsupported SVG commands encountered during import, retained for
    /// diagnostics without blocking the editable subset.
    public var unsupportedSVGCommands: [String]

    public init(anchors: [VectorAnchorPoint] = [],
                isClosed: Bool = false,
                strokeColor: VColor? = .black,
                strokeWidth: Double = 1,
                fillColor: VColor? = nil,
                unsupportedSVGCommands: [String] = []) {
        self.anchors = anchors
        self.isClosed = isClosed
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.fillColor = fillColor
        self.unsupportedSVGCommands = unsupportedSVGCommands
    }

    public var isValid: Bool {
        anchors.count >= 2 && (strokeColor != nil || fillColor != nil)
    }

    public var isEmpty: Bool { anchors.isEmpty }
}
