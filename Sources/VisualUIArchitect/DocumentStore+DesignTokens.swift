import Foundation
import VUACore
import LayerEngine

extension DocumentStore {
    var designTokens: [DesignToken] { document.designTokens }

    func addDesignToken(_ token: DesignToken) {
        mutate { $0.designTokens.append(token) }
        repositoryStatus = "Added design token '\(token.name)'."
    }

    func addDefaultDesignTokens() {
        let defaults: [DesignToken] = [
            DesignToken(name: "Primary Color", kind: .color,
                        value: .color(VColor(red: 0.18, green: 0.38, blue: 0.92, alpha: 1))),
            DesignToken(name: "Body Type", kind: .typography,
                        value: .typography(size: 15, weight: .regular)),
            DesignToken(name: "Space 8", kind: .spacing, value: .spacing(8)),
            DesignToken(name: "Radius 8", kind: .cornerRadius, value: .cornerRadius(8)),
            DesignToken(name: "Panel Shadow", kind: .shadow,
                        value: .shadow(ShadowSpec(color: VColor(red: 0, green: 0, blue: 0, alpha: 0.25),
                                                  radius: 12, x: 0, y: 6))),
            DesignToken(name: "Accent Gradient", kind: .gradient,
                        value: .gradient(GradientSpec(stops: [
                            GradientStop(color: VColor(red: 0.18, green: 0.38, blue: 0.92, alpha: 1), location: 0),
                            GradientStop(color: VColor(red: 0.1, green: 0.62, blue: 0.54, alpha: 1), location: 1)
                        ]))),
            DesignToken(name: "Glass Material", kind: .material, value: .material("regularMaterial"))
        ]
        mutate { doc in
            let existing = Set(doc.designTokens.map { $0.name })
            doc.designTokens.append(contentsOf: defaults.filter { !existing.contains($0.name) })
        }
        repositoryStatus = "Added default design tokens."
    }

    func applyTokenToSelection(_ token: DesignToken) {
        guard let id = selection.first else { return }
        mutate { doc in
            LayerTree.update(id, in: &doc.roots) { layer in
                switch token.value {
                case .color(let color):
                    layer.style.backgroundColor = color
                    layer.style.tokens.backgroundColor = token.id
                case .typography(let size, let weight):
                    layer.style.fontSize = size
                    layer.style.fontWeight = weight
                    layer.style.tokens.typography = token.id
                case .spacing:
                    layer.style.tokens.spacing = token.id
                case .cornerRadius(let radius):
                    layer.style.cornerRadius = radius
                    layer.style.tokens.cornerRadius = token.id
                case .shadow(let shadow):
                    layer.style.shadow = shadow
                    layer.style.tokens.shadow = token.id
                case .gradient(let gradient):
                    layer.style.gradient = gradient
                    layer.style.tokens.gradient = token.id
                case .material:
                    layer.style.tokens.material = token.id
                }
            }
        }
        repositoryStatus = "Applied token '\(token.name)'."
    }
}
