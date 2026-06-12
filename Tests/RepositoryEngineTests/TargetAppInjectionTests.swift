import XCTest
@testable import RepositoryEngine

final class TargetAppInjectionTests: XCTestCase {
    func testBlocksTargetsOutsideRepository() throws {
        let repo = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repo) }
        let outside = repo.deletingLastPathComponent().appendingPathComponent("Outside-\(UUID().uuidString).swift")
        let original = "Text(\"Outside\")"
        try original.write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }

        let result = TargetAppInjection.apply(.init(
            repoRoot: repo,
            targetFile: outside.path,
            generatedSource: "Text(\"Injected\")",
            allowDirtyRepo: true,
            allowFullFileReplacement: true))

        XCTAssertTrue(result.hasBlocker)
        XCTAssertTrue(result.diagnostics.contains { $0.code == .targetOutsideRepository })
        XCTAssertFalse(result.wroteFile)
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), original)
    }

    func testBlocksUnsupportedTargetExtension() throws {
        let repo = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repo) }
        let target = repo.appendingPathComponent("Notes.txt")
        try "not swift".write(to: target, atomically: true, encoding: .utf8)

        let result = TargetAppInjection.preview(.init(
            repoRoot: repo,
            targetFile: "Notes.txt",
            generatedSource: "Text(\"Injected\")",
            allowDirtyRepo: true,
            allowFullFileReplacement: true))

        XCTAssertTrue(result.hasBlocker)
        XCTAssertTrue(result.diagnostics.contains { $0.code == .unsupportedTarget })
        XCTAssertEqual(result.targetURL, target.standardizedFileURL.resolvingSymlinksInPath())
    }

    func testFullFileReplacementRequiresExplicitOptIn() throws {
        let repo = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repo) }
        let target = repo.appendingPathComponent("Target.swift")
        let original = """
        import SwiftUI

        struct Target: View {
            var body: some View { Text("Old") }
        }
        """
        let generated = """
        import SwiftUI

        struct Target: View {
            var body: some View { Text("New") }
        }
        """
        try original.write(to: target, atomically: true, encoding: .utf8)

        let blockedPreview = TargetAppInjection.preview(.init(
            repoRoot: repo,
            targetFile: "Target.swift",
            generatedSource: generated,
            expectedHash: SourceSafety.hash(of: original),
            allowDirtyRepo: true))

        XCTAssertEqual(blockedPreview.replacementMode, .fullFile)
        XCTAssertTrue(blockedPreview.previewDiff.contains("Text(\"New\")"))
        XCTAssertTrue(blockedPreview.diagnostics.contains { $0.code == .fullFileReplacementBlocked })

        let blockedApply = TargetAppInjection.apply(.init(
            repoRoot: repo,
            targetFile: "Target.swift",
            generatedSource: generated,
            expectedHash: SourceSafety.hash(of: original),
            allowDirtyRepo: true))

        XCTAssertFalse(blockedApply.wroteFile)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), original)

        let allowedApply = TargetAppInjection.apply(.init(
            repoRoot: repo,
            targetFile: "Target.swift",
            generatedSource: generated,
            expectedHash: SourceSafety.hash(of: original),
            allowDirtyRepo: true,
            allowFullFileReplacement: true))

        XCTAssertTrue(allowedApply.wroteFile)
        XCTAssertTrue(allowedApply.diagnostics.contains { $0.code == .noInjectionMarker && $0.severity == .warning })
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), generated)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vua-target-injection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
