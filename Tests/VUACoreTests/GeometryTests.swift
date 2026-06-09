import XCTest
@testable import VUACore

final class GeometryTests: XCTestCase {
    func testRectContainsAndIntersect() {
        let r = VRect(x: 0, y: 0, width: 100, height: 50)
        XCTAssertTrue(r.contains(VPoint(x: 50, y: 25)))
        XCTAssertFalse(r.contains(VPoint(x: 150, y: 25)))
        XCTAssertTrue(r.intersects(VRect(x: 90, y: 40, width: 20, height: 20)))
        XCTAssertFalse(r.intersects(VRect(x: 200, y: 200, width: 10, height: 10)))
    }

    func testRectUnion() {
        let a = VRect(x: 0, y: 0, width: 10, height: 10)
        let b = VRect(x: 20, y: 20, width: 10, height: 10)
        let u = a.union(b)
        XCTAssertEqual(u, VRect(x: 0, y: 0, width: 30, height: 30))
    }

    func testColorHexRoundTrip() {
        let c = VColor(hex: "#3478F6")
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.hexString, "#3478F6")
    }

    func testRelativeLuminanceBounds() {
        XCTAssertEqual(VColor.black.relativeLuminance, 0, accuracy: 0.0001)
        XCTAssertEqual(VColor.white.relativeLuminance, 1, accuracy: 0.0001)
    }

    func testDocumentLayerLookup() {
        let child = Layer(name: "Child", kind: .label)
        let root = Layer(name: "Root", kind: .container, children: [child])
        let doc = Document(roots: [root])
        XCTAssertEqual(doc.layer(id: child.id)?.name, "Child")
        XCTAssertEqual(doc.allLayers.count, 2)
    }
}
