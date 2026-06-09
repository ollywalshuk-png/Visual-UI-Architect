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

    func testUnsupportedTargetThrows() {
        var doc = sampleDocument()
        doc.codeGenTarget = .flutter
        XCTAssertThrowsError(try CodeGenService().generate(doc))
    }
}
