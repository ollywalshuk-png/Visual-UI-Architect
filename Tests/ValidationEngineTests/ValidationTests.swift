import XCTest
import VUACore
@testable import ValidationEngine

final class ValidationTests: XCTestCase {
    func testContrastRatioBlackOnWhite() {
        let ratio = WCAG.contrastRatio(.black, .white)
        XCTAssertEqual(ratio, 21, accuracy: 0.01)
        XCTAssertTrue(WCAG.passesAA(ratio, largeText: false))
    }

    func testLowContrastIsFlagged() {
        let label = Layer(
            name: "Faint Label", kind: .label,
            frame: VRect(x: 0, y: 0, width: 100, height: 20),
            style: LayerStyle(backgroundColor: VColor(hex: "#EEEEEE"),
                              foregroundColor: VColor(hex: "#DDDDDD")),
            text: "Hi")
        let doc = Document(roots: [label])
        let report = ValidationService().validate(doc)
        XCTAssertTrue(report.issues.contains { $0.category == .contrast && $0.severity == .error })
    }

    func testSmallTouchTargetWarnsOnTouchPlatform() {
        let button = Layer(
            name: "Tiny", kind: .button,
            frame: VRect(x: 0, y: 0, width: 20, height: 20),
            text: "x")
        let doc = Document(roots: [button], activeDevice: .iPhone15Pro)
        let report = ValidationService().validate(doc)
        XCTAssertTrue(report.issues.contains { $0.category == .touchTarget })
    }

    func testClippingChildIsFlagged() {
        let child = Layer(name: "Overflow", kind: .label,
                          frame: VRect(x: 90, y: 0, width: 100, height: 20), text: "x")
        let parent = Layer(name: "Box", kind: .panel,
                           frame: VRect(x: 0, y: 0, width: 100, height: 100),
                           children: [child])
        let doc = Document(roots: [parent])
        let report = ValidationService().validate(doc)
        XCTAssertTrue(report.issues.contains { $0.category == .clipping })
    }
}
