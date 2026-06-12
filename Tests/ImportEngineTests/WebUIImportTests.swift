import XCTest
import RepositoryEngine
import VUACore
@testable import ImportEngine

final class WebUIImportTests: XCTestCase {
    func testHTMLProjectDiscoversAndImportsEditableLayers() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let html = #"""
        <!doctype html>
        <html>
          <head><title>Marketing Home</title></head>
          <body>
            <main id="home" style="width: 480px; height: 260px; background-color: #101820;">
              <h1 data-testid="heroTitle" style="font-size: 28px; color: #ffffff;">Launch faster</h1>
              <button id="startButton" style="width: 140px; height: 44px; border-radius: 8px;">Start</button>
              <input id="emailField" placeholder="Email" />
              <canvas id="chart"></canvas>
            </main>
          </body>
        </html>
        """#
        try html.write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

        let summary = ImportFrameworkDetector().detect(root: root)
        XCTAssertEqual(summary.framework, .htmlCSS)
        XCTAssertEqual(summary.implementationState, .implemented)
        XCTAssertEqual(summary.rating, .yellow)
        XCTAssertEqual(summary.screenCount, 1)

        let candidate = try XCTUnwrap(summary.candidates.first)
        XCTAssertEqual(candidate.viewName, "MarketingHome")
        XCTAssertTrue(candidate.hasAnchors)
        XCTAssertGreaterThan(candidate.supportedElementCount, 3)
        XCTAssertEqual(candidate.unsupportedElementCount, 1)

        let imported = try XCTUnwrap(ImportCoordinator().importCandidate(candidate))
        XCTAssertFalse(imported.hasAnchors)
        let layers = imported.view.roots.flatMap { $0.flattened() }
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "home" && $0.kind.isGroupLike })
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "heroTitle" && $0.text == "Launch faster" })
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "startButton" && $0.kind == .button && $0.frame.width == 140 })
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "emailField" && $0.kind == .text && $0.text == "Email" })
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "chart" && $0.isLocked })
    }

    func testReactPackageWithoutRenderableFilesRemainsFoundationOnly() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        try #"{"dependencies":{"react":"latest"}}"#
            .write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let summary = ImportFrameworkDetector().detect(root: root)
        XCTAssertEqual(summary.framework, .react)
        XCTAssertEqual(summary.implementationState, .foundationOnly)
        XCTAssertEqual(summary.candidates, [])
    }

    func testReactJSXFileDiscoversStaticComponentCandidate() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        try #"{"dependencies":{"react":"latest"}}"#
            .write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try #"""
        export default function ControlPanel() {
          return (
            <section id="panel" style={{ width: 360, height: 160 }}>
              <button data-vua-anchor="playButton">Play</button>
              <input id="level" type="range" />
            </section>
          );
        }
        """#.write(to: root.appendingPathComponent("ControlPanel.jsx"), atomically: true, encoding: .utf8)

        let summary = ImportFrameworkDetector().detect(root: root)
        XCTAssertEqual(summary.framework, .react)
        XCTAssertEqual(summary.implementationState, .implemented)
        XCTAssertEqual(summary.rating, .yellow)

        let candidate = try XCTUnwrap(summary.candidates.first)
        XCTAssertEqual(candidate.viewName, "ControlPanel")
        let imported = try XCTUnwrap(ImportCoordinator().importCandidate(candidate))
        let layers = imported.view.roots.flatMap { $0.flattened() }
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "playButton" && $0.kind == .button })
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "level" && $0.kind == .slider })
    }

    func testFlutterProjectDiscoversAndImportsStaticWidgetTree() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        try "dependencies:\n  flutter:\n    sdk: flutter\n"
            .write(to: root.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("lib"), withIntermediateDirectories: true)
        try #"""
        import 'package:flutter/material.dart';

        class MixerScreen extends StatelessWidget {
          const MixerScreen({super.key});

          @override
          Widget build(BuildContext context) {
            return Scaffold(
              body: Container(
                key: const ValueKey('mixerRoot'),
                width: 420,
                height: 240,
                child: Column(
                  children: [
                    const Text('Mixer', style: TextStyle(fontSize: 24)),
                    ElevatedButton(
                      key: const ValueKey('playButton'),
                      onPressed: () {},
                      child: const Text('Play'),
                    ),
                    Slider(
                      key: const ValueKey('gainSlider'),
                      value: 0.5,
                      onChanged: (_) {},
                    ),
                    Switch(
                      key: const ValueKey('bypassSwitch'),
                      value: true,
                      onChanged: (_) {},
                    ),
                  ],
                ),
              ),
            );
          }
        }
        """#.write(to: root.appendingPathComponent("lib/main.dart"), atomically: true, encoding: .utf8)

        let summary = ImportFrameworkDetector().detect(root: root)
        XCTAssertEqual(summary.framework, .flutter)
        XCTAssertEqual(summary.implementationState, .implemented)
        XCTAssertEqual(summary.rating, .yellow)
        XCTAssertEqual(summary.screenCount, 1)

        let candidate = try XCTUnwrap(summary.candidates.first)
        XCTAssertEqual(candidate.viewName, "MixerScreen")
        XCTAssertTrue(candidate.hasAnchors)
        XCTAssertGreaterThanOrEqual(candidate.supportedElementCount, 6)

        let imported = try XCTUnwrap(ImportCoordinator().importCandidate(candidate))
        XCTAssertFalse(imported.hasAnchors)
        let layers = imported.view.roots.flatMap { $0.flattened() }
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "mixerRoot" && $0.kind.isGroupLike && $0.frame.width == 420 })
        XCTAssertFalse(layers.contains { $0.tags.contains("widget:Scaffold") && $0.binding?.anchorID == "mixerRoot" })
        XCTAssertTrue(layers.contains { $0.text == "Mixer" && $0.kind == .label && $0.style.fontSize == 24 })
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "playButton" && $0.kind == .button && $0.text == "Play" })
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "gainSlider" && $0.kind == .slider })
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "bypassSwitch" && $0.kind == .toggle })
    }

    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vua-web-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
