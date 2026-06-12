import XCTest
import VUACore
@testable import ExportIntegrityEngine

final class ExportIntegrityPipelineTests: XCTestCase {
    func testExportCanBundleAdditionalTargetSources() throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("vua-export-multi-target-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: destination) }

        let button = Layer(
            name: "Play Button",
            kind: .button,
            frame: VRect(x: 20, y: 40, width: 120, height: 44),
            text: "Play",
            binding: CodeBinding(filePath: "Panel.swift", anchorID: "playButton"))
        let document = Document(name: "Export Panel", roots: [button])
        let targets: [CodeGenTarget] = [.react, .reactNative, .htmlCSS, .electronRenderer, .flutter, .uiKit, .appKit]

        let result = try ExportIntegrityPipeline().export(
            document: document,
            request: ExportRequest(
                destination: destination,
                moduleName: "GeneratedUI",
                viewName: "PanelView",
                includeControlsLibrary: false,
                additionalCodeGenTargets: targets))

        XCTAssertFalse(result.hasErrors)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.generatedCodePath.path))
        XCTAssertEqual(Set(result.additionalCodeFiles.map(\.target)), Set(targets))

        let filesByTarget = Dictionary(uniqueKeysWithValues: result.additionalCodeFiles.map { ($0.target, $0) })
        XCTAssertTrue(try contents(of: filesByTarget[.react]).contains("export default function PanelView"))
        XCTAssertTrue(try contents(of: filesByTarget[.reactNative]).contains("export default function PanelView"))
        XCTAssertTrue(try contents(of: filesByTarget[.htmlCSS]).contains("<!doctype html>"))
        XCTAssertTrue(try contents(of: filesByTarget[.electronRenderer]).contains("electron-renderer"))
        XCTAssertTrue(try contents(of: filesByTarget[.flutter]).contains("class PanelView extends StatelessWidget"))
        XCTAssertTrue(try contents(of: filesByTarget[.uiKit]).contains("final class PanelViewController: UIViewController"))
        XCTAssertTrue(try contents(of: filesByTarget[.appKit]).contains("final class PanelViewController: NSViewController"))

        let report = try String(contentsOf: result.reportPath, encoding: .utf8)
        XCTAssertTrue(report.contains("## Generated Sources"))
        XCTAssertTrue(report.contains("Targets/React/PanelView.jsx"))
        XCTAssertTrue(report.contains("Targets/AppKit/PanelViewController.swift"))
    }

    private func contents(of file: ExportedCodeFile?) throws -> String {
        let file = try XCTUnwrap(file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path.path), file.relativePath)
        return try String(contentsOf: file.path, encoding: .utf8)
    }
}
