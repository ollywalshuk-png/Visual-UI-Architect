import Foundation

/// The kind of UI component a layer represents. Drives code generation and
/// the inspector UI. Extensible: `.custom` carries an arbitrary type name.
public enum LayerKind: Codable, Hashable, Sendable {
    case container          // generic grouping view (VStack/HStack/ZStack target)
    case panel              // styled background container
    case button
    case label
    case text               // multi-line / editable text
    case image
    case slider
    case knob               // rotary control (plugin/synth UI)
    case fader              // linear (usually vertical) level control
    case meter              // level / VU meter
    case toggle
    case background
    case control            // generic interactive control
    case group              // grouping container for general UI (Phase 7)
    case shape(ShapeKind)   // vector shape layer
    case line               // straight line / arrow / connector
    case vectorPath         // editable Bezier/freehand vector path
    case polygon            // regular polygon / star
    case gradient           // gradient fill layer
    case mask               // masking layer (clips its group/siblings)
    case custom(typeName: String)

    /// Plugin/synth controls that carry AU-style parameter metadata.
    public var isPluginControl: Bool {
        switch self {
        case .knob, .fader, .meter, .slider, .toggle: return true
        default: return false
        }
    }

    /// Container kinds that hold and clip/stack children.
    public var isGroupLike: Bool {
        switch self {
        case .container, .panel, .background, .group: return true
        default: return false
        }
    }

    public var displayName: String {
        switch self {
        case .container: return "Container"
        case .panel: return "Panel"
        case .button: return "Button"
        case .label: return "Label"
        case .text: return "Text"
        case .image: return "Image"
        case .slider: return "Slider"
        case .knob: return "Knob"
        case .fader: return "Fader"
        case .meter: return "Meter"
        case .toggle: return "Toggle"
        case .background: return "Background"
        case .control: return "Control"
        case .group: return "Group"
        case .shape(let s): return s.displayName
        case .line: return "Line"
        case .vectorPath: return "Vector Path"
        case .polygon: return "Polygon"
        case .gradient: return "Gradient"
        case .mask: return "Mask"
        case .custom(let name): return name
        }
    }
}

/// Visual styling shared across layer kinds. Optional fields are only emitted
/// in generated code when set, keeping output clean.
public struct LayerStyle: Codable, Hashable, Sendable {
    public var backgroundColor: VColor?
    public var foregroundColor: VColor?
    public var cornerRadius: Double
    public var borderColor: VColor?
    public var borderWidth: Double
    public var opacity: Double
    public var fontSize: Double?
    public var fontWeight: FontWeight?
    /// Gradient fill (overrides `backgroundColor` when set).
    public var gradient: GradientSpec?
    public var shadow: ShadowSpec?
    public var rotationDegrees: Double
    public var blurRadius: Double

    public enum FontWeight: String, Codable, Hashable, Sendable, CaseIterable {
        case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black
    }

    public init(
        backgroundColor: VColor? = nil,
        foregroundColor: VColor? = nil,
        cornerRadius: Double = 0,
        borderColor: VColor? = nil,
        borderWidth: Double = 0,
        opacity: Double = 1,
        fontSize: Double? = nil,
        fontWeight: FontWeight? = nil,
        gradient: GradientSpec? = nil,
        shadow: ShadowSpec? = nil,
        rotationDegrees: Double = 0,
        blurRadius: Double = 0
    ) {
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.cornerRadius = cornerRadius
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.opacity = opacity
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.gradient = gradient
        self.shadow = shadow
        self.rotationDegrees = rotationDegrees
        self.blurRadius = blurRadius
    }

    public static let `default` = LayerStyle()
}

/// Links a layer back to its representation in source code, enabling
/// bidirectional sync. Without a binding, a layer is "design-only" until
/// the code-generation engine materialises it.
public struct CodeBinding: Codable, Hashable, Sendable {
    /// Repository-relative path to the source file.
    public var filePath: String
    /// Stable identifier emitted into source as a marker comment / accessibilityIdentifier.
    public var anchorID: String
    /// Line range last known to contain this layer's code (1-based, inclusive).
    public var lineRange: ClosedRange<Int>?

    public init(filePath: String, anchorID: String, lineRange: ClosedRange<Int>? = nil) {
        self.filePath = filePath
        self.anchorID = anchorID
        self.lineRange = lineRange
    }
}

/// Physical/engineering unit a plugin parameter is expressed in.
public enum ControlUnit: String, Codable, Hashable, Sendable, CaseIterable {
    case generic, decibels, hertz, percent, seconds, milliseconds, semitones, degrees, ratio

    public var symbol: String {
        switch self {
        case .generic: return ""
        case .decibels: return "dB"
        case .hertz: return "Hz"
        case .percent: return "%"
        case .seconds: return "s"
        case .milliseconds: return "ms"
        case .semitones: return "st"
        case .degrees: return "°"
        case .ratio: return ":1"
        }
    }
}

/// AU/plugin-style control metadata attached to interactive components
/// (knobs, faders, meters, sliders, switches). Drives code generation and a
/// future audio-unit parameter export.
public struct ControlMetadata: Codable, Hashable, Sendable {
    /// Stable parameter identifier (e.g. "cutoff", "resonance").
    public var parameterID: String
    public var displayName: String
    public var minValue: Double
    public var maxValue: Double
    public var defaultValue: Double
    public var unit: ControlUnit
    /// false → stepped/discrete control (switches, enum selectors).
    public var isContinuous: Bool
    /// Number of discrete steps when not continuous (e.g. a 3-way switch).
    public var stepCount: Int?
    /// Phase 20: optional behaviour metadata. Optional fields decode from
    /// older documents without migration because missing optional keys become nil.
    public var behaviourType: String?
    public var interactionMode: String?
    public var responseCurve: String?
    public var bindingName: String?
    public var midiCC: Int?
    public var auParameterID: String?
    public var automationEnabled: Bool?
    public var rotationStartDegrees: Double?
    public var rotationEndDegrees: Double?

    public init(
        parameterID: String,
        displayName: String? = nil,
        minValue: Double = 0,
        maxValue: Double = 1,
        defaultValue: Double = 0,
        unit: ControlUnit = .generic,
        isContinuous: Bool = true,
        stepCount: Int? = nil,
        behaviourType: String? = nil,
        interactionMode: String? = nil,
        responseCurve: String? = nil,
        bindingName: String? = nil,
        midiCC: Int? = nil,
        auParameterID: String? = nil,
        automationEnabled: Bool? = nil,
        rotationStartDegrees: Double? = nil,
        rotationEndDegrees: Double? = nil
    ) {
        self.parameterID = parameterID
        self.displayName = displayName ?? parameterID
        self.minValue = minValue
        self.maxValue = maxValue
        self.defaultValue = defaultValue
        self.unit = unit
        self.isContinuous = isContinuous
        self.stepCount = stepCount
        self.behaviourType = behaviourType
        self.interactionMode = interactionMode
        self.responseCurve = responseCurve
        self.bindingName = bindingName
        self.midiCC = midiCC
        self.auParameterID = auParameterID
        self.automationEnabled = automationEnabled
        self.rotationStartDegrees = rotationStartDegrees
        self.rotationEndDegrees = rotationEndDegrees
    }

    /// Clamps a value to the parameter's range.
    public func clamp(_ value: Double) -> Double {
        Swift.min(maxValue, Swift.max(minValue, value))
    }

    /// Normalised position (0...1) of the default within the range.
    public var normalizedDefault: Double {
        guard maxValue > minValue else { return 0 }
        return (defaultValue - minValue) / (maxValue - minValue)
    }
}

/// A single node in the layer tree. Children make it a container.
public struct Layer: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var kind: LayerKind

    /// Frame in the coordinate space of the parent layer (or canvas root).
    public var frame: VRect
    public var style: LayerStyle

    /// Display text for text-bearing kinds (label/button/text).
    public var text: String?
    /// Reference to an imported asset (image/background/vector) by id.
    public var assetID: UUID?

    public var isVisible: Bool
    public var isLocked: Bool
    /// Tint shown in the layer panel (organisational, not rendered).
    public var labelColor: VColor?

    public var constraints: [LayerConstraint]
    public var binding: CodeBinding?

    /// AU/plugin parameter metadata for interactive controls (nil otherwise).
    public var control: ControlMetadata?

    // MARK: Phase 7 — advanced layer attributes
    /// Semantic role (organisational; affects validation/presets, not rendering).
    public var role: LayerRole?
    /// Free-text note shown in the inspector.
    public var notes: String?
    /// Organisational tags.
    public var tags: [String]
    /// Group disclosure state in the layer panel.
    public var isCollapsed: Bool
    /// Hide from generated SwiftUI accessibility tree (`.accessibilityHidden`).
    public var isAccessibilityHidden: Bool
    /// Line geometry when `kind == .line`.
    public var line: LineSpec?
    /// Polygon geometry when `kind == .polygon`.
    public var polygon: PolygonSpec?
    /// Editable vector path geometry when `kind == .vectorPath`.
    public var vectorPath: VectorPathSpec?
    /// Masking applied to this layer (and its children when it's a group).
    public var mask: MaskSpec?
    /// Clip the layer's content to this shape (`.clipShape` in generated code).
    public var clipShape: ShapeKind?
    /// Asset/image transform metadata (scale, flip, crop, blend, texture hook).
    public var assetTransform: AssetTransformSpec?
    /// Non-destructive raster paint strokes over an image/background layer.
    public var rasterPaint: RasterPaintSpec?
    /// When set, this layer is an *instance* of the component with this id
    /// (its children are derived from the component master). Phase 15.
    public var componentID: UUID?
    /// Selected variant for a component instance. Nil means inherit base master.
    public var componentVariantID: UUID?
    /// Local instance overrides retained when the component/variant re-syncs.
    public var componentOverrides: [ComponentOverride]
    /// Properties this instance may not override.
    public var lockedComponentProperties: Set<String>

    public var children: [Layer]

    public init(
        id: UUID = UUID(),
        name: String,
        kind: LayerKind,
        frame: VRect = .zero,
        style: LayerStyle = .default,
        text: String? = nil,
        assetID: UUID? = nil,
        isVisible: Bool = true,
        isLocked: Bool = false,
        labelColor: VColor? = nil,
        constraints: [LayerConstraint] = [],
        binding: CodeBinding? = nil,
        control: ControlMetadata? = nil,
        role: LayerRole? = nil,
        notes: String? = nil,
        tags: [String] = [],
        isCollapsed: Bool = false,
        isAccessibilityHidden: Bool = false,
        line: LineSpec? = nil,
        polygon: PolygonSpec? = nil,
        vectorPath: VectorPathSpec? = nil,
        mask: MaskSpec? = nil,
        clipShape: ShapeKind? = nil,
        assetTransform: AssetTransformSpec? = nil,
        rasterPaint: RasterPaintSpec? = nil,
        componentID: UUID? = nil,
        componentVariantID: UUID? = nil,
        componentOverrides: [ComponentOverride] = [],
        lockedComponentProperties: Set<String> = [],
        children: [Layer] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.frame = frame
        self.style = style
        self.text = text
        self.assetID = assetID
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.labelColor = labelColor
        self.constraints = constraints
        self.binding = binding
        self.control = control
        self.role = role
        self.notes = notes
        self.tags = tags
        self.isCollapsed = isCollapsed
        self.isAccessibilityHidden = isAccessibilityHidden
        self.line = line
        self.polygon = polygon
        self.vectorPath = vectorPath
        self.mask = mask
        self.clipShape = clipShape
        self.assetTransform = assetTransform
        self.rasterPaint = rasterPaint
        self.componentID = componentID
        self.componentVariantID = componentVariantID
        self.componentOverrides = componentOverrides
        self.lockedComponentProperties = lockedComponentProperties
        self.children = children
    }

    /// True when this layer is an instance of a reusable component.
    public var isComponentInstance: Bool { componentID != nil }

    public var isContainer: Bool {
        if kind.isGroupLike { return true }
        return !children.isEmpty
    }
}
