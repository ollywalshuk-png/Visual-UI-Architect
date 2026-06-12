import Foundation
import VUACore
import LayerEngine

public struct ComponentResolvedInstance: Hashable, Sendable {
    public var componentID: UUID
    public var variantID: UUID?
    public var variantName: String
    public var resolvedRoot: Layer
    public var appliedOverrides: [ComponentOverride]
    public var inheritedFromBase: Bool
}

public enum ComponentVariantResolution {
    public static func resolveMaster(component: Component, variantID: UUID?) -> (root: Layer, variantName: String, inherited: Bool) {
        guard let variant = component.variant(id: variantID) else {
            return (LayerTree.cloneWithNewIDs(component.master), "Base", false)
        }
        let base = LayerTree.cloneWithNewIDs(component.master)
        let resolved = merge(base: base, overlay: variant.master)
        return (resolved, variant.name, true)
    }

    public static func resolveInstance(_ instance: Layer, component: Component) -> ComponentResolvedInstance? {
        guard instance.componentID == component.id else { return nil }
        var resolved = resolveMaster(component: component, variantID: instance.componentVariantID)
        resolved.root.name = instance.name
        resolved.root.frame.origin = instance.frame.origin
        resolved.root.componentID = instance.componentID
        resolved.root.componentVariantID = instance.componentVariantID
        resolved.root.componentOverrides = instance.componentOverrides
        resolved.root.lockedComponentProperties = instance.lockedComponentProperties
        let applied = applyOverrides(instance.componentOverrides, locked: instance.lockedComponentProperties, to: &resolved.root)
        return ComponentResolvedInstance(
            componentID: component.id,
            variantID: instance.componentVariantID,
            variantName: resolved.variantName,
            resolvedRoot: resolved.root,
            appliedOverrides: applied,
            inheritedFromBase: resolved.inherited)
    }

    public static func merge(base: Layer, overlay: Layer) -> Layer {
        var result = base
        if !overlay.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.name = overlay.name
        }
        result.kind = overlay.kind
        if overlay.frame != .zero { result.frame = overlay.frame }
        result.style = merge(base: base.style, overlay: overlay.style)
        if let text = overlay.text { result.text = text }
        if let asset = overlay.assetID { result.assetID = asset }
        result.isVisible = overlay.isVisible
        result.isLocked = overlay.isLocked
        if let role = overlay.role { result.role = role }
        if let notes = overlay.notes { result.notes = notes }
        result.tags = Array(Set(base.tags + overlay.tags)).sorted()
        if !overlay.constraints.isEmpty { result.constraints = overlay.constraints }
        if let control = overlay.control { result.control = control }
        if let line = overlay.line { result.line = line }
        if let polygon = overlay.polygon { result.polygon = polygon }
        if let vectorPath = overlay.vectorPath { result.vectorPath = vectorPath }
        if let mask = overlay.mask { result.mask = mask }
        if let clipShape = overlay.clipShape { result.clipShape = clipShape }
        if let transform = overlay.assetTransform { result.assetTransform = transform }
        if let paint = overlay.rasterPaint { result.rasterPaint = paint }

        var children: [Layer] = []
        let maxCount = max(base.children.count, overlay.children.count)
        for index in 0..<maxCount {
            if index < base.children.count, index < overlay.children.count {
                children.append(merge(base: base.children[index], overlay: overlay.children[index]))
            } else if index < base.children.count {
                children.append(base.children[index])
            } else {
                children.append(overlay.children[index])
            }
        }
        result.children = children
        return result
    }

    @discardableResult
    public static func applyOverrides(_ overrides: [ComponentOverride], locked: Set<String>, to root: inout Layer) -> [ComponentOverride] {
        var applied: [ComponentOverride] = []
        for override in overrides where !locked.contains(override.property) {
            if apply(override, to: &root) {
                applied.append(override)
            }
        }
        return applied
    }

    private static func apply(_ override: ComponentOverride, to root: inout Layer) -> Bool {
        switch override.property {
        case "text":
            return mutateFirstTextLayer(in: &root) { $0.text = override.valueDescription }
        case "backgroundColor":
            guard let color = VColor(hex: override.valueDescription) else { return false }
            return mutateFirstStyledLayer(in: &root) { $0.style.backgroundColor = color }
        case "foregroundColor":
            guard let color = VColor(hex: override.valueDescription) else { return false }
            return mutateFirstStyledLayer(in: &root) { $0.style.foregroundColor = color }
        case "cornerRadius":
            guard let value = Double(override.valueDescription) else { return false }
            return mutateFirstStyledLayer(in: &root) { $0.style.cornerRadius = value }
        case "opacity":
            guard let value = Double(override.valueDescription) else { return false }
            return mutateFirstStyledLayer(in: &root) { $0.style.opacity = value }
        case "frame.size":
            let parts = override.valueDescription.lowercased().split(separator: "x")
            guard parts.count == 2, let width = Double(parts[0].trimmingCharacters(in: .whitespaces)),
                  let height = Double(parts[1].trimmingCharacters(in: .whitespaces)) else { return false }
            root.frame.size = VSize(width: width, height: height)
            return true
        default:
            if override.property.hasPrefix("token.") {
                return applyTokenOverride(override, to: &root)
            }
            return false
        }
    }

    private static func applyTokenOverride(_ override: ComponentOverride, to root: inout Layer) -> Bool {
        guard let id = UUID(uuidString: override.valueDescription) else { return false }
        let key = String(override.property.dropFirst("token.".count))
        return mutateFirstStyledLayer(in: &root) { layer in
            switch key {
            case "backgroundColor": layer.style.tokens.backgroundColor = id
            case "foregroundColor": layer.style.tokens.foregroundColor = id
            case "typography": layer.style.tokens.typography = id
            case "cornerRadius": layer.style.tokens.cornerRadius = id
            case "shadow": layer.style.tokens.shadow = id
            case "gradient": layer.style.tokens.gradient = id
            case "material": layer.style.tokens.material = id
            case "border": layer.style.tokens.border = id
            case "opacity": layer.style.tokens.opacity = id
            case "glass": layer.style.tokens.glass = id
            default: return
            }
        }
    }

    private static func merge(base: LayerStyle, overlay: LayerStyle) -> LayerStyle {
        var result = base
        if let value = overlay.backgroundColor { result.backgroundColor = value }
        if let value = overlay.foregroundColor { result.foregroundColor = value }
        if overlay.cornerRadius != LayerStyle.default.cornerRadius { result.cornerRadius = overlay.cornerRadius }
        if let value = overlay.borderColor { result.borderColor = value }
        if overlay.borderWidth != LayerStyle.default.borderWidth { result.borderWidth = overlay.borderWidth }
        if overlay.opacity != LayerStyle.default.opacity { result.opacity = overlay.opacity }
        if let value = overlay.fontSize { result.fontSize = value }
        if let value = overlay.fontWeight { result.fontWeight = value }
        if let value = overlay.gradient { result.gradient = value }
        if let value = overlay.shadow { result.shadow = value }
        if overlay.rotationDegrees != LayerStyle.default.rotationDegrees { result.rotationDegrees = overlay.rotationDegrees }
        if overlay.blurRadius != LayerStyle.default.blurRadius { result.blurRadius = overlay.blurRadius }
        result.tokens = merge(base: base.tokens, overlay: overlay.tokens)
        return result
    }

    private static func merge(base: LayerTokenReferences, overlay: LayerTokenReferences) -> LayerTokenReferences {
        LayerTokenReferences(
            backgroundColor: overlay.backgroundColor ?? base.backgroundColor,
            foregroundColor: overlay.foregroundColor ?? base.foregroundColor,
            typography: overlay.typography ?? base.typography,
            spacing: overlay.spacing ?? base.spacing,
            cornerRadius: overlay.cornerRadius ?? base.cornerRadius,
            shadow: overlay.shadow ?? base.shadow,
            gradient: overlay.gradient ?? base.gradient,
            material: overlay.material ?? base.material,
            border: overlay.border ?? base.border,
            elevation: overlay.elevation ?? base.elevation,
            opacity: overlay.opacity ?? base.opacity,
            glass: overlay.glass ?? base.glass)
    }

    private static func mutateFirstTextLayer(in layer: inout Layer, _ mutate: (inout Layer) -> Void) -> Bool {
        if layer.text != nil || layer.kind == .button || layer.kind == .label || layer.kind == .text {
            mutate(&layer)
            return true
        }
        for index in layer.children.indices {
            if mutateFirstTextLayer(in: &layer.children[index], mutate) { return true }
        }
        return false
    }

    private static func mutateFirstStyledLayer(in layer: inout Layer, _ mutate: (inout Layer) -> Void) -> Bool {
        if layer.kind == .button || layer.kind == .panel || layer.kind == .shape(.roundedRectangle) || layer.children.isEmpty {
            mutate(&layer)
            return true
        }
        for index in layer.children.indices {
            if mutateFirstStyledLayer(in: &layer.children[index], mutate) { return true }
        }
        return false
    }
}

public extension ComponentEngine {
    static func resolveInstance(_ instance: Layer, component: Component) -> ComponentResolvedInstance? {
        ComponentVariantResolution.resolveInstance(instance, component: component)
    }

    static func standardButtonVariants(for component: Component) -> [ComponentVariant] {
        [
            buttonVariant(component: component, name: "Primary") { layer in
                layer.tags.append("variant:primary")
            },
            buttonVariant(component: component, name: "Secondary") { layer in
                layer.style.backgroundColor = .clear
                layer.style.foregroundColor = VColor(hex: "#3478F6")
                layer.style.borderColor = VColor(hex: "#3478F6")
                layer.style.borderWidth = 1
                layer.tags.append("variant:secondary")
            },
            buttonVariant(component: component, name: "Danger") { layer in
                layer.style.backgroundColor = VColor(hex: "#FF3B30")
                layer.style.foregroundColor = .white
                layer.tags.append("variant:danger")
            },
            buttonVariant(component: component, name: "Glass") { layer in
                layer.style.opacity = 0.92
                layer.style.blurRadius = 0
                layer.tags.append("variant:glass")
            },
            buttonVariant(component: component, name: "Disabled") { layer in
                layer.style.opacity = 0.45
                layer.isLocked = true
                layer.tags.append("variant:disabled")
            }
        ]
    }

    private static func buttonVariant(component: Component, name: String, mutate: (inout Layer) -> Void) -> ComponentVariant {
        var master = LayerTree.cloneWithNewIDs(component.master)
        master.name = "\(component.name) \(name)"
        mutateFirstButton(in: &master, mutate)
        return ComponentVariant(name: name, master: master)
    }

    @discardableResult
    private static func mutateFirstButton(in layer: inout Layer, _ mutate: (inout Layer) -> Void) -> Bool {
        if layer.kind == .button {
            mutate(&layer)
            return true
        }
        for index in layer.children.indices {
            if mutateFirstButton(in: &layer.children[index], mutate) { return true }
        }
        return false
    }
}
