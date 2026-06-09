import Foundation
import VUACore

/// Phase 12 hardening checks: duplicate identities (layer IDs, source
/// anchors, asset names), off-canvas layers, hidden-parent traps, dead
/// gradients, and z-order mistakes that silently break generated UIs.
public struct HardeningValidator: Sendable {
    public init() {}

    public func validate(_ document: Document, bundleURL: URL? = nil) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let all = document.allLayers

        // --- Duplicate layer IDs (broken paste/preset) — corrupts selection,
        // undo and codegen anchors, so it's an error.
        var idCounts: [UUID: Int] = [:]
        for layer in all { idCounts[layer.id, default: 0] += 1 }
        for (id, count) in idCounts where count > 1 {
            let name = all.first(where: { $0.id == id })?.name ?? "?"
            issues.append(ValidationIssue(
                severity: .error, category: .structure,
                message: "Layer ID of “\(name)” appears \(count)× — IDs must be unique.",
                recommendation: "Re-duplicate the layer (paste assigns fresh IDs) or delete the copies.",
                layerIDs: [id]))
        }

        // --- Duplicate source anchors: two different layers bound to the same
        // accessibility anchor would patch the same source node.
        var anchorOwners: [String: [Layer]] = [:]
        for layer in all {
            if let binding = layer.binding { anchorOwners[binding.anchorID, default: []].append(layer) }
        }
        for (anchor, owners) in anchorOwners where owners.count > 1 {
            issues.append(ValidationIssue(
                severity: .error, category: .structure,
                message: "\(owners.count) layers share the source anchor “\(anchor)” — Apply would patch the same code node twice.",
                recommendation: "Give each bound layer a unique anchor.",
                layerIDs: owners.map(\.id)))
        }

        // --- Duplicate names: harmless to render, confusing to navigate.
        var nameCounts: [String: Int] = [:]
        for layer in all { nameCounts[layer.name, default: 0] += 1 }
        for (name, count) in nameCounts where count > 1 {
            issues.append(ValidationIssue(
                severity: .info, category: .structure,
                message: "\(count) layers are named “\(name)”.",
                recommendation: "Rename for unambiguous layer-panel navigation.",
                layerIDs: []))
        }

        // --- Off-canvas: a visible layer entirely outside the device canvas.
        let canvas = VRect(x: 0, y: 0, width: document.canvasSize.width, height: document.canvasSize.height)
        func walk(_ layers: [Layer], offset: VPoint) {
            for layer in layers {
                let abs = VRect(x: layer.frame.minX + offset.x, y: layer.frame.minY + offset.y,
                                width: layer.frame.width, height: layer.frame.height)
                if layer.isVisible, layer.frame.width > 0, layer.frame.height > 0, !abs.intersects(canvas) {
                    issues.append(ValidationIssue(
                        severity: .warning, category: .layout,
                        message: "\(layer.name) is entirely off-canvas (at \(Int(abs.minX)), \(Int(abs.minY))).",
                        recommendation: "Move it into the \(Int(canvas.width))×\(Int(canvas.height)) canvas or delete it.",
                        layerIDs: [layer.id]))
                }
                walk(layer.children, offset: VPoint(x: abs.minX, y: abs.minY))
            }
        }
        walk(document.roots, offset: VPoint(x: 0, y: 0))

        // --- Hidden parent with visible children: children silently vanish.
        for layer in all where !layer.isVisible {
            let visibleChildren = layer.children.filter(\.isVisible)
            if !visibleChildren.isEmpty {
                issues.append(ValidationIssue(
                    severity: .info, category: .structure,
                    message: "\(layer.name) is hidden but contains \(visibleChildren.count) visible child(ren) — they won't render.",
                    recommendation: "Unhide the parent or hide the children explicitly.",
                    layerIDs: [layer.id]))
            }
        }

        // --- Fully transparent gradient: every stop has alpha ≈ 0.
        for layer in all {
            if let gradient = layer.style.gradient, !gradient.stops.isEmpty,
               gradient.stops.allSatisfy({ $0.color.alpha <= 0.001 }) {
                issues.append(ValidationIssue(
                    severity: .warning, category: .structure,
                    message: "\(layer.name) has a gradient whose every stop is fully transparent.",
                    recommendation: "Raise at least one stop's alpha, or remove the gradient.",
                    layerIDs: [layer.id]))
            }
        }

        // --- Sibling z-order traps. Later siblings draw on top.
        func zOrderChecks(_ siblings: [Layer]) {
            let controls: Set<LayerKind> = [.button, .slider, .knob, .fader, .meter, .toggle, .control]
            for (i, layer) in siblings.enumerated() {
                // A background layer stacked above interactive controls.
                if layer.kind == .background {
                    let buried = siblings[..<i].filter { controls.contains($0.kind) && $0.frame.intersects(layer.frame) }
                    if !buried.isEmpty {
                        issues.append(ValidationIssue(
                            severity: .warning, category: .structure,
                            message: "Background “\(layer.name)” is stacked above \(buried.count) control(s) — they may be unreachable.",
                            recommendation: "Send the background to the back.",
                            layerIDs: [layer.id] + buried.map(\.id)))
                    }
                }
                // An opaque panel fully covering an earlier control.
                if layer.kind == .panel, layer.isVisible, layer.style.opacity >= 0.99,
                   (layer.style.backgroundColor?.alpha ?? 0) >= 0.99 {
                    for earlier in siblings[..<i]
                    where controls.contains(earlier.kind) && layer.frame.containsRect(earlier.frame) {
                        issues.append(ValidationIssue(
                            severity: .warning, category: .structure,
                            message: "“\(earlier.name)” is hidden behind the opaque panel “\(layer.name)”.",
                            recommendation: "Reorder the layers or make the panel transparent.",
                            layerIDs: [earlier.id, layer.id]))
                    }
                }
                zOrderChecks(layer.children)
            }
        }
        zOrderChecks(document.roots)

        issues.append(contentsOf: assetChecks(document, bundleURL: bundleURL))
        return issues
    }

    // MARK: Asset safety

    private func assetChecks(_ document: Document, bundleURL: URL?) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let fm = FileManager.default

        // Exact, case-only, and sanitised name collisions. Exports write asset
        // files into one Resources/ folder — collisions overwrite each other.
        var byName: [String: Int] = [:]
        var byLower: [String: [String]] = [:]
        var bySanitised: [String: [String]] = [:]
        for asset in document.assets {
            byName[asset.name, default: 0] += 1
            byLower[asset.name.lowercased(), default: []].append(asset.name)
            bySanitised[Self.sanitised(asset.name), default: []].append(asset.name)
        }
        for (name, count) in byName where count > 1 {
            issues.append(ValidationIssue(
                severity: .error, category: .asset,
                message: "\(count) assets are both named “\(name)” — exports would overwrite one with the other.",
                recommendation: "Rename one of them.", layerIDs: []))
        }
        for (_, names) in byLower where Set(names).count > 1 {
            issues.append(ValidationIssue(
                severity: .warning, category: .asset,
                message: "Assets \(names.map { "“\($0)”" }.joined(separator: " and ")) differ only by case — they collide on case-insensitive file systems (APFS default, Git on macOS).",
                recommendation: "Rename one so the names differ by more than case.", layerIDs: []))
        }
        for (key, names) in bySanitised where Set(names).count > 1 {
            issues.append(ValidationIssue(
                severity: .warning, category: .asset,
                message: "Assets \(names.map { "“\($0)”" }.joined(separator: " and ")) sanitise to the same exported filename “\(key)”.",
                recommendation: "Rename one — exported resources must be unique after sanitising.", layerIDs: []))
        }

        // Missing / external asset files (absolute paths only — bundle-relative
        // paths are resolved and verified by the app's AssetResolver).
        for asset in document.assets where asset.path.hasPrefix("/") {
            if !fm.fileExists(atPath: asset.path) {
                issues.append(ValidationIssue(
                    severity: .error, category: .asset,
                    message: "Asset “\(asset.name)” is missing on disk (\(asset.path)).",
                    recommendation: "Re-import the file or fix the reference.", layerIDs: []))
            } else if let bundle = bundleURL, !asset.path.hasPrefix(bundle.path) {
                issues.append(ValidationIssue(
                    severity: .info, category: .asset,
                    message: "Asset “\(asset.name)” lives outside the project bundle — it will be copied in on next save.",
                    recommendation: nil, layerIDs: []))
            }
        }
        return issues
    }

    /// Mirrors the exporter's resource-name sanitising: lowercase, and any
    /// non-alphanumeric run becomes a single underscore.
    public static func sanitised(_ name: String) -> String {
        var out = ""
        var lastWasUnderscore = false
        for ch in name.lowercased() {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                lastWasUnderscore = false
            } else if !lastWasUnderscore {
                out.append("_")
                lastWasUnderscore = true
            }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}

private extension VRect {
    func containsRect(_ other: VRect) -> Bool {
        other.minX >= minX && other.minY >= minY
            && other.maxX <= maxX && other.maxY <= maxY
    }
}
