import XCTest
import RepositoryEngine
import VUACore
@testable import ImportEngine

final class AppleUIImportTests: XCTestCase {
    func testUIKitProjectDiscoversAndImportsStaticViewController() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        try #"""
        import UIKit

        final class MixerViewController: UIViewController {
            override func viewDidLoad() {
                super.viewDidLoad()

                let panel = UIView()
                panel.accessibilityIdentifier = "mixerPanel"
                panel.frame = CGRect(x: 20, y: 20, width: 320, height: 180)

                let titleLabel = UILabel()
                titleLabel.text = "Mixer"
                titleLabel.font = .systemFont(ofSize: 24)
                titleLabel.accessibilityIdentifier = "titleLabel"
                titleLabel.frame = CGRect(x: 16, y: 16, width: 180, height: 32)

                let playButton = UIButton(type: .system)
                playButton.setTitle("Play", for: .normal)
                playButton.accessibilityIdentifier = "playButton"
                playButton.frame = CGRect(x: 16, y: 64, width: 120, height: 44)

                let gainSlider = UISlider()
                gainSlider.accessibilityIdentifier = "gainSlider"
                gainSlider.frame = CGRect(x: 16, y: 120, width: 220, height: 32)

                let bypassSwitch = UISwitch()
                bypassSwitch.accessibilityIdentifier = "bypassSwitch"
                bypassSwitch.frame = CGRect(x: 250, y: 116, width: 52, height: 32)

                let meter = CustomMeterView()
                meter.accessibilityIdentifier = "meterView"
                meter.frame = CGRect(x: 260, y: 16, width: 40, height: 80)

                view.addSubview(panel)
                panel.addSubview(titleLabel)
                panel.addSubview(playButton)
                panel.addSubview(gainSlider)
                panel.addSubview(bypassSwitch)
                panel.addSubview(meter)
            }
        }
        """#.write(to: root.appendingPathComponent("MixerViewController.swift"), atomically: true, encoding: .utf8)

        let summary = ImportFrameworkDetector().detect(root: root)
        XCTAssertEqual(summary.framework, .uiKit)
        XCTAssertEqual(summary.implementationState, .implemented)
        XCTAssertEqual(summary.rating, .yellow)
        XCTAssertEqual(summary.screenCount, 1)

        let candidate = try XCTUnwrap(summary.candidates.first)
        XCTAssertEqual(candidate.viewName, "MixerViewController")
        XCTAssertTrue(candidate.hasAnchors)
        XCTAssertGreaterThanOrEqual(candidate.supportedElementCount, 5)
        XCTAssertEqual(candidate.unsupportedElementCount, 1)

        let imported = try XCTUnwrap(ImportCoordinator().importCandidate(candidate))
        XCTAssertFalse(imported.hasAnchors)
        let layers = imported.view.roots.flatMap { $0.flattened() }
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "mixerPanel" && $0.kind.isGroupLike && $0.frame.width == 320 })
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "titleLabel" && $0.kind == .label && $0.text == "Mixer" && $0.style.fontSize == 24 })
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "playButton" && $0.kind == .button && $0.text == "Play" })
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "gainSlider" && $0.kind == .slider })
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "bypassSwitch" && $0.kind == .toggle })
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "meterView" && $0.isLocked })
    }

    func testAppKitProjectDiscoversAndImportsStaticViewController() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        try #"""
        import AppKit

        final class MixerViewController: NSViewController {
            override func viewDidLoad() {
                super.viewDidLoad()

                let panel = NSView()
                panel.identifier = NSUserInterfaceItemIdentifier("mixerPanel")
                panel.frame = NSRect(x: 24, y: 24, width: 360, height: 190)

                let titleField = NSTextField(labelWithString: "Mixer")
                titleField.identifier = .init("titleField")
                titleField.font = NSFont.systemFont(ofSize: 22)
                titleField.frame = NSRect(x: 18, y: 142, width: 180, height: 28)

                let playButton = NSButton(title: "Play", target: nil, action: nil)
                playButton.identifier = .init("playButton")
                playButton.frame = NSRect(x: 18, y: 86, width: 120, height: 38)

                let gainSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
                gainSlider.identifier = NSUserInterfaceItemIdentifier("gainSlider")
                gainSlider.frame = NSRect(x: 18, y: 42, width: 220, height: 24)

                let bypassSwitch = NSSwitch()
                bypassSwitch.identifier = .init("bypassSwitch")
                bypassSwitch.frame = NSRect(x: 260, y: 82, width: 80, height: 32)

                view.addSubview(panel)
                panel.addSubview(titleField)
                panel.addSubview(playButton)
                panel.addSubview(gainSlider)
                panel.addSubview(bypassSwitch)
            }
        }
        """#.write(to: root.appendingPathComponent("MixerViewController.swift"), atomically: true, encoding: .utf8)

        let summary = ImportFrameworkDetector().detect(root: root)
        XCTAssertEqual(summary.framework, .appKit)
        XCTAssertEqual(summary.implementationState, .implemented)
        XCTAssertEqual(summary.rating, .yellow)
        XCTAssertEqual(summary.screenCount, 1)

        let candidate = try XCTUnwrap(summary.candidates.first)
        XCTAssertEqual(candidate.viewName, "MixerViewController")
        XCTAssertTrue(candidate.hasAnchors)

        let imported = try XCTUnwrap(ImportCoordinator().importCandidate(candidate))
        let layers = imported.view.roots.flatMap { $0.flattened() }
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "mixerPanel" && $0.kind.isGroupLike && $0.frame.width == 360 })
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "titleField" && $0.kind == .label && $0.text == "Mixer" && $0.style.fontSize == 22 })
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "playButton" && $0.kind == .button && $0.text == "Play" })
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "gainSlider" && $0.kind == .slider })
        XCTAssertTrue(layers.contains { $0.binding?.anchorID == "bypassSwitch" && $0.kind == .toggle })
    }

    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vua-apple-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
