import XCTest
import VUACore
import LayerEngine
import CodeGenEngine
@testable import ComponentEngine

final class ComponentVariantResolutionTests: XCTestCase {
    func testStandardButtonVariantsResolveInheritedStylesAndOverrides() throws {
        let foregroundToken = DesignToken(name: "Button Foreground", kind: .color, value: .color(.white))
        let radiusToken = DesignToken(name: "Button Radius", kind: .cornerRadius, value: .cornerRadius(10))
        let button = Layer(
            name: "Button",
            kind: .button,
            frame: VRect(x: 0, y: 0, width: 120, height: 44),
            style: LayerStyle(
                backgroundColor: VColor(hex: "#3478F6"),
                foregroundColor: .white,
                cornerRadius: 10,
                tokens: LayerTokenReferences(
                    foregroundColor: foregroundToken.id,
                    cornerRadius: radiusToken.id)),
            text: "Save")
        let master = Layer(
            name: "Button",
            kind: .group,
            frame: VRect(x: 0, y: 0, width: 120, height: 44),
            children: [button])
        var component = Component(name: "Button", master: master)
        component.variants = ComponentEngine.standardButtonVariants(for: component)

        XCTAssertEqual(component.variants.map(\.name), ["Primary", "Secondary", "Danger", "Glass", "Disabled"])

        let danger = try XCTUnwrap(component.variants.first { $0.name == "Danger" })
        var instance = ComponentEngine.makeInstance(of: component, variantID: danger.id, at: VPoint(x: 20, y: 30))
        instance.componentOverrides = [
            ComponentOverride(property: "text", valueDescription: "Delete"),
            ComponentOverride(property: "token.foregroundColor", valueDescription: foregroundToken.id.uuidString),
            ComponentOverride(property: "opacity", valueDescription: "0.72")
        ]

        let resolved = try XCTUnwrap(ComponentEngine.resolveInstance(instance, component: component))
        let resolvedButton = try XCTUnwrap(resolved.resolvedRoot.flattened().first { $0.kind == .button })
        XCTAssertEqual(resolved.variantName, "Danger")
        XCTAssertTrue(resolved.inheritedFromBase)
        XCTAssertEqual(resolved.resolvedRoot.frame.origin, VPoint(x: 20, y: 30))
        XCTAssertEqual(resolvedButton.text, "Delete")
        XCTAssertEqual(resolvedButton.style.backgroundColor, VColor(hex: "#FF3B30"))
        XCTAssertEqual(resolvedButton.style.tokens.foregroundColor, foregroundToken.id)
        XCTAssertEqual(resolvedButton.style.tokens.cornerRadius, radiusToken.id)
        XCTAssertEqual(resolvedButton.style.opacity, 0.72, accuracy: 0.001)
        XCTAssertEqual(resolved.appliedOverrides.map(\.property), ["text", "token.foregroundColor", "opacity"])
    }

    func testLockedOverridesDoNotApplyAndCodegenCarriesOverrideMetadata() throws {
        let button = Layer(
            name: "Button",
            kind: .button,
            frame: VRect(x: 0, y: 0, width: 120, height: 44),
            style: LayerStyle(backgroundColor: VColor(hex: "#3478F6"), foregroundColor: .white, cornerRadius: 8),
            text: "Save")
        let master = Layer(name: "Button", kind: .group, frame: VRect(x: 0, y: 0, width: 120, height: 44), children: [button])
        var component = Component(name: "Button", master: master)
        component.variants = ComponentEngine.standardButtonVariants(for: component)
        let glass = try XCTUnwrap(component.variants.first { $0.name == "Glass" })
        var instance = ComponentEngine.makeInstance(of: component, variantID: glass.id, at: .zero)
        instance.componentOverrides = [
            ComponentOverride(property: "text", valueDescription: "Launch"),
            ComponentOverride(property: "foregroundColor", valueDescription: "#111111")
        ]
        instance.lockedComponentProperties = ["foregroundColor"]

        let resolved = try XCTUnwrap(ComponentEngine.resolveInstance(instance, component: component))
        let resolvedButton = try XCTUnwrap(resolved.resolvedRoot.flattened().first { $0.kind == .button })
        XCTAssertEqual(resolvedButton.text, "Launch")
        XCTAssertEqual(resolvedButton.style.foregroundColor, .white)
        XCTAssertEqual(resolved.appliedOverrides.map(\.property), ["text"])

        let document = Document(name: "ComponentCodegen", roots: [instance], components: [component])
        let source = try CodeGenService().generate(document).contents
        XCTAssertTrue(source.contains("var overrides: [String: String] = [:]"))
        XCTAssertTrue(source.contains("ButtonComponentView(variant: \"Glass\", overrides: [\"text\": \"Launch\", \"foregroundColor\": \"#111111\"])"))
    }
}
