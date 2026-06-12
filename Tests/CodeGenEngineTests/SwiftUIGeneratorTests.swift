import XCTest
import VUACore
import LayerEngine
@testable import CodeGenEngine

final class SwiftUIGeneratorTests: XCTestCase {
    private func sampleDocument() -> Document {
        let button = Layer(
            name: "Play Button",
            kind: .button,
            frame: VRect(x: 20, y: 40, width: 120, height: 44),
            style: LayerStyle(backgroundColor: VColor(hex: "#3478F6"),
                              foregroundColor: .white, cornerRadius: 8),
            text: "Play",
            binding: CodeBinding(filePath: "UI.swift", anchorID: "playButton"))
        let panel = Layer(
            name: "Transport",
            kind: .panel,
            frame: VRect(x: 0, y: 0, width: 320, height: 120),
            children: [button])
        return Document(name: "Synth", roots: [panel])
    }

    func testGeneratesCompilableStructure() throws {
        let source = try SwiftUIGenerator().generate(document: sampleDocument())
        XCTAssertEqual(source.fileName, "GeneratedView.swift")
        XCTAssertTrue(source.contents.contains("import SwiftUI"))
        XCTAssertTrue(source.contents.contains("struct GeneratedView: View"))
        XCTAssertTrue(source.contents.contains("var body: some View"))
        // Balanced braces is a cheap proxy for structural validity.
        let opens = source.contents.filter { $0 == "{" }.count
        let closes = source.contents.filter { $0 == "}" }.count
        XCTAssertEqual(opens, closes)
    }

    func testEmitsBindingAnchorAndText() throws {
        let source = try SwiftUIGenerator().generate(document: sampleDocument()).contents
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"playButton\")"))
        XCTAssertTrue(source.contains("Text(\"Play\")"))
        XCTAssertTrue(source.contains(".position(x: 80, y: 62)"))
    }

    func testMultiTargetServiceGeneratesReactHTMLFlutterAndNativeTargets() throws {
        let service = CodeGenService()
        let cases: [(CodeGenTarget, String, [String])] = [
            (.react, "GeneratedView.jsx", ["export default function GeneratedView", "data-vua-anchor='playButton'", "onClick={viewModel.playButtonAction"]),
            (.reactNative, "GeneratedView.native.jsx", ["import { Image, Pressable, StyleSheet, Switch, Text, View }", "nativeID='playButton'", "onPress={viewModel.playButtonAction"]),
            (.htmlCSS, "index.html", ["<!doctype html>", "data-vua-anchor=\"playButton\"", "data-vua-action=\"playButtonAction\""]),
            (.electronRenderer, "renderer.html", ["data-vua-target", "electron-renderer", "data-vua-anchor=\"playButton\""]),
            (.flutter, "GeneratedView.dart", ["class GeneratedView extends StatelessWidget", "Positioned(", "ElevatedButton(onPressed:"]),
            (.uiKit, "GeneratedViewController.swift", ["import UIKit", "final class GeneratedViewController: UIViewController", "accessibilityIdentifier = \"playButton\""]),
            (.appKit, "GeneratedViewController.swift", ["import AppKit", "final class GeneratedViewController: NSViewController", "NSUserInterfaceItemIdentifier(\"playButton\")"])
        ]

        for (target, fileName, expectedSnippets) in cases {
            var doc = sampleDocument()
            doc.codeGenTarget = target
            let source = try service.generate(doc)
            XCTAssertEqual(source.fileName, fileName, target.displayName)
            for snippet in expectedSnippets {
                XCTAssertTrue(source.contents.contains(snippet), "\(target.displayName) missing \(snippet)\n\(source.contents)")
            }
        }
    }

    func testMultiTargetExportsCarryBehaviourBindingPlan() throws {
        let cutoff = Layer(
            name: "Cutoff",
            kind: .slider,
            frame: VRect(x: 20, y: 20, width: 180, height: 28),
            binding: CodeBinding(filePath: "Panel.swift", anchorID: "cutoffSlider"),
            control: ControlMetadata(
                parameterID: "cutoff",
                displayName: "Cutoff",
                minValue: 20,
                maxValue: 20_000,
                defaultValue: 1_000,
                unit: .hertz,
                behaviourType: "horizontalSlider",
                bindingName: "viewModel.cutoff",
                midiCC: 74,
                auParameterID: "filter.cutoff",
                automationEnabled: true))
        let settings = Layer(
            name: "Settings",
            kind: .button,
            frame: VRect(x: 20, y: 58, width: 120, height: 36),
            text: "Settings",
            binding: CodeBinding(filePath: "Panel.swift", anchorID: "settingsButton"),
            control: ControlMetadata(
                parameterID: "settings",
                isContinuous: false,
                behaviourType: "buttonPress",
                bindingName: "settings"),
            role: .navigation)
        let cpu = Layer(
            name: "CPU",
            kind: .text,
            frame: VRect(x: 20, y: 104, width: 160, height: 32),
            text: "CPU",
            binding: CodeBinding(filePath: "Panel.swift", anchorID: "cpuReadout"),
            control: ControlMetadata(
                parameterID: "cpu",
                displayName: "CPU",
                minValue: 0,
                maxValue: 100,
                defaultValue: 42,
                unit: .percent,
                behaviourType: "valueDisplay",
                interactionMode: "readOnly",
                bindingName: "viewModel.cpu"))
        let document = Document(name: "Bindings", roots: [cutoff, settings, cpu])
        let service = CodeGenService()
        let cases: [(CodeGenTarget, [String])] = [
            (.react, [
                "export const vuaBindingPlan = [",
                "propertyName: 'viewModelCutoff'",
                "midiCC: 74",
                "auParameterID: 'filter.cutoff'",
                "data-vua-binding-kind='value'",
                "data-vua-au-parameter='filter.cutoff'",
                "onClick={viewModel.navigateSettings"
            ]),
            (.reactNative, [
                "export const vuaBindingPlan = [",
                "{/* VUA binding: value viewModelCutoff",
                "{/* VUA binding: navigation navigateSettings"
            ]),
            (.htmlCSS, [
                "id=\"vua-binding-plan\"",
                "\"propertyName\":\"viewModelCutoff\"",
                "\"auParameterID\":\"filter.cutoff\"",
                "data-vua-binding-kind=\"value\"",
                "data-vua-action-binding=\"navigateSettings\""
            ]),
            (.electronRenderer, [
                "window.vuaBindingPlan = [",
                "\"actionName\":\"navigateSettings\"",
                "data-vua-target"
            ]),
            (.flutter, [
                "const List<Map<String, Object?>> vuaBindingPlan = [",
                "'propertyName': 'viewModelCutoff'",
                "// VUA binding: value viewModelCutoff"
            ]),
            (.uiKit, [
                "private let vuaBindingPlan: [[String: Any]] = [",
                "\"propertyName\": \"viewModelCutoff\"",
                "// VUA binding: navigation navigateSettings"
            ]),
            (.appKit, [
                "private let vuaBindingPlan: [[String: Any]] = [",
                "\"auParameterID\": \"filter.cutoff\"",
                "// VUA binding: readOnly viewModelCpu"
            ])
        ]

        for (target, snippets) in cases {
            var doc = document
            doc.codeGenTarget = target
            let source = try service.generate(doc).contents
            for snippet in snippets {
                XCTAssertTrue(source.contains(snippet), "\(target.displayName) missing \(snippet)\n\(source)")
            }
        }
    }

    func testUnsupportedTargetThrows() {
        var doc = sampleDocument()
        doc.codeGenTarget = .jetpackCompose
        XCTAssertThrowsError(try CodeGenService().generate(doc))
    }
}
