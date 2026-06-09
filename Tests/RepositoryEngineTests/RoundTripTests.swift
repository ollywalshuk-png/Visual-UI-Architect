import XCTest
import VUACore
@testable import RepositoryEngine

final class RoundTripTests: XCTestCase {
    private let source = """
    import SwiftUI

    struct DemoView: View {
        var body: some View {
            ZStack(alignment: .topLeading) {
                Text("Title")
                    .font(.system(size: 22))
                    .frame(width: 200, height: 28)
                    .position(x: 120, y: 40)
                    .accessibilityIdentifier("titleLabel")
                Button("Play") {}
                    .frame(width: 120, height: 44)
                    .position(x: 80, y: 120)
                    .accessibilityIdentifier("playButton")
            }
        }
    }
    """

    func testParsesViewAndAnchors() {
        let views = SwiftUIParser().parse(source: source, filePath: "Demo.swift")
        XCTAssertEqual(views.count, 1)
        let layers = views[0].roots.flatMap { $0.flattened() }
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "titleLabel" })
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "playButton" })
    }

    func testParsesExplicitPosition() {
        let views = SwiftUIParser().parse(source: source, filePath: "Demo.swift")
        let play = views[0].roots.flatMap { $0.flattened() }.first { $0.binding?.anchorID == "playButton" }
        XCTAssertNotNil(play)
        // position x:80 with width 120 → origin.x == 20
        XCTAssertEqual(play!.frame.origin.x, 20, accuracy: 0.5)
        XCTAssertEqual(play!.frame.width, 120, accuracy: 0.5)
    }

    func testRoundTripMovePreservesFidelity() throws {
        let writer = SourceFidelityWriter()
        let updated = try writer.updatePositions(
            in: source, changes: ["playButton": VRect(x: 200, y: 300, width: 120, height: 44)])
        // New center is (260, 322).
        XCTAssertTrue(updated.contains(".position(x: 260, y: 322)"))
        // Untouched node and comments/imports preserved.
        XCTAssertTrue(updated.contains("import SwiftUI"))
        XCTAssertTrue(updated.contains(".accessibilityIdentifier(\"titleLabel\")"))
        // Re-parsing yields the moved frame.
        let reparsed = SwiftUIParser().parse(source: updated, filePath: "Demo.swift")
        let play = reparsed[0].roots.flatMap { $0.flattened() }.first { $0.binding?.anchorID == "playButton" }
        XCTAssertEqual(play!.frame.origin.x, 200, accuracy: 0.5)
        XCTAssertEqual(play!.frame.origin.y, 300, accuracy: 0.5)
    }
}
