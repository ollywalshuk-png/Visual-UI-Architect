import Foundation
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

    func testSemanticAnalyzerExtractsStateNavigationBindingsAndCustomSignals() {
        let source = #"""
        import SwiftUI
        import Observation

        @Observable
        final class PlayerViewModel {
            var tracks: [Track] = []
            func load() async {}
            func play(_ track: Track) {}
        }

        struct MasonryLayout: Layout {}

        struct PlayerScreen: View {
            @State private var path = NavigationPath()
            @State private var isPresented = false
            @Binding var enabled: Bool
            @EnvironmentObject var session: SessionStore
            @StateObject private var viewModel = PlayerViewModel()

            var body: some View {
                NavigationStack(path: $path) {
                    if enabled {
                        List {
                            ForEach(viewModel.tracks, id: \.id) { track in
                                TrackRow(track: track)
                                    .appCardStyle()
                            }
                        }
                        .navigationDestination(for: Track.self) { track in
                            DetailScreen(track: track)
                        }
                        .sheet(isPresented: $isPresented) {
                            SettingsScreen()
                        }
                        .task { await viewModel.load() }
                    }
                }
            }
        }

        struct TrackRow: View {
            let track: Track
            var body: some View { Text(track.name) }
        }
        """#

        let view = SwiftUISemanticAnalyzer().analyze(source: source, filePath: "PlayerScreen.swift")
            .first { $0.viewName == "PlayerScreen" }
        XCTAssertEqual(view?.viewName, "PlayerScreen")
        XCTAssertTrue(view?.properties.contains { $0.name == "path" && $0.wrappers.contains(.state) && $0.isNavigationPath } == true)
        XCTAssertTrue(view?.properties.contains { $0.name == "enabled" && $0.wrappers.contains(.binding) } == true)
        XCTAssertTrue(view?.properties.contains { $0.name == "session" && $0.wrappers.contains(.environmentObject) } == true)
        XCTAssertTrue(view?.viewModelProperties.contains { $0.name == "viewModel" } == true)
        XCTAssertTrue(view?.forEachLoops.contains { $0.dataExpression == "viewModel.tracks" && $0.idExpression == "\\.id" && $0.isModelBacked } == true)
        XCTAssertTrue(view?.navigation.contains { $0.kind == "NavigationStack" && $0.pathBinding == "path" } == true)
        XCTAssertTrue(view?.navigation.contains { $0.kind == "navigationDestination" && $0.destinationType == "Track" } == true)
        XCTAssertTrue(view?.navigation.contains { $0.kind == "sheet" } == true)
        XCTAssertTrue(view?.asyncHooks.contains { $0.kind == "task" && $0.expression.contains("viewModel.load") } == true)
        XCTAssertEqual(view?.conditionalBranchCount, 1)
        XCTAssertTrue(view?.customModifiers.contains("appCardStyle") == true)
        XCTAssertTrue(view?.customViewCalls.contains("DetailScreen") == true)
        XCTAssertTrue(view?.customViewCalls.contains("SettingsScreen") == true)
        XCTAssertTrue(view?.customLayoutTypes.contains("MasonryLayout") == true)
        XCTAssertTrue(view?.observableTypes.contains("PlayerViewModel") == true)

        let relationships = view?.relationships ?? []
        XCTAssertTrue(relationships.contains {
            $0.kind == .viewModel && $0.source == "viewModel" && $0.target == "PlayerViewModel"
        })
        XCTAssertTrue(relationships.contains {
            $0.kind == .environmentObject && $0.source == "session" && $0.target == "SessionStore"
        })
        XCTAssertTrue(relationships.contains {
            $0.kind == .navigationPath && $0.source == "path" && $0.target == "NavigationPath"
        })
        XCTAssertTrue(relationships.contains {
            $0.kind == .dataSource && $0.source == "viewModel.tracks" && $0.target == "track"
        })
        XCTAssertTrue(relationships.contains {
            $0.kind == .navigationDestination && $0.target == "Track"
        })
        XCTAssertTrue(relationships.contains {
            $0.kind == .modalPresentation && $0.source == "sheet" && $0.target == "SettingsScreen"
        })
        XCTAssertTrue(relationships.contains {
            $0.kind == .customView && $0.target == "TrackRow" && $0.detail == "local view"
        })
        XCTAssertTrue(relationships.contains {
            $0.kind == .asyncWork && $0.source == "task" && ($0.detail ?? "").contains("viewModel.load")
        })
    }

    func testSemanticViewDecodesLegacyPayloadWithoutRelationships() throws {
        let json = #"""
        {
          "viewName": "LegacyScreen",
          "filePath": "LegacyScreen.swift",
          "properties": [],
          "forEachLoops": [],
          "navigation": [],
          "asyncHooks": [],
          "conditionalBranchCount": 0,
          "customModifiers": [],
          "customViewCalls": [],
          "customLayoutTypes": [],
          "observableTypes": []
        }
        """#

        let decoded = try JSONDecoder().decode(SwiftUISemanticView.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.viewName, "LegacyScreen")
        XCTAssertEqual(decoded.relationships, [])
    }
}
