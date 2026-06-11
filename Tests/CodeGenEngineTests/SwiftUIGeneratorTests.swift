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

    func testUnsupportedTargetThrows() {
        var doc = sampleDocument()
        doc.codeGenTarget = .jetpackCompose
        XCTAssertThrowsError(try CodeGenService().generate(doc))
    }
}
