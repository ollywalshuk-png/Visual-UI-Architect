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

    func testNewScreenCreationRequiresOptInAndWritesOwnershipMarkers() throws {
        let repo = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repo) }
        try runGit(["init", "-q"], in: repo)
        let target = repo.appendingPathComponent("Sources/App/NewScreen.swift")
        let generated = """
        import SwiftUI

        struct NewScreen: View {
            var body: some View { Text("New") }
        }
        """

        let blocked = TargetAppInjection.preview(.init(
            repoRoot: repo,
            targetFile: "Sources/App/NewScreen.swift",
            generatedSource: generated,
            allowDirtyRepo: true))

        XCTAssertEqual(blocked.replacementMode, .fullFile)
        XCTAssertTrue(blocked.hasBlocker)
        XCTAssertTrue(blocked.diagnostics.contains { $0.code == .createFileBlocked })
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))

        let preview = TargetAppInjection.preview(.init(
            repoRoot: repo,
            targetFile: "Sources/App/NewScreen.swift",
            generatedSource: generated,
            allowDirtyRepo: true,
            allowCreateFile: true))

        XCTAssertEqual(preview.replacementMode, .newFile)
        XCTAssertFalse(preview.hasBlocker)
        XCTAssertTrue(preview.previewDiff.contains("// VUA:BEGIN-GENERATED-FILE"))
        XCTAssertTrue(preview.previewDiff.contains("struct NewScreen: View"))
        XCTAssertTrue(preview.rollbackPlan.contains { $0.contains("rm -f -- Sources/App/NewScreen.swift") })
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))

        let applied = TargetAppInjection.apply(.init(
            repoRoot: repo,
            targetFile: "Sources/App/NewScreen.swift",
            generatedSource: generated,
            allowDirtyRepo: true,
            allowCreateFile: true))

        XCTAssertEqual(applied.replacementMode, .newFile)
        XCTAssertTrue(applied.wroteFile)
        let written = try String(contentsOf: target, encoding: .utf8)
        XCTAssertTrue(written.contains("// VUA:BEGIN-GENERATED-FILE"))
        XCTAssertTrue(written.contains("// VUA:Owner=Visual UI Architect"))
        XCTAssertTrue(written.contains("struct NewScreen: View"))
        XCTAssertTrue(written.contains("// VUA:END-GENERATED-FILE"))
    }

    func testEmptyExistingSwiftFileIsNotTreatedAsNewFile() throws {
        let repo = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repo) }
        let target = repo.appendingPathComponent("Empty.swift")
        try "".write(to: target, atomically: true, encoding: .utf8)

        let blocked = TargetAppInjection.preview(.init(
            repoRoot: repo,
            targetFile: "Empty.swift",
            generatedSource: "import SwiftUI\n",
            allowDirtyRepo: true))

        XCTAssertEqual(blocked.replacementMode, .fullFile)
        XCTAssertTrue(blocked.diagnostics.contains { $0.code == .fullFileReplacementBlocked })
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vua-target-injection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func runGit(_ args: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = directory
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
