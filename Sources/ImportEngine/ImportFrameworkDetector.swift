import Foundation
import RepositoryEngine

public struct ImportFrameworkDetector: Sendable {
    public init() {}

    public func detect(root: URL) -> ImportProjectSummary {
        let files = RepositoryScanner(root: root).scan()
        let fm = FileManager.default
        let packageJSON = root.appendingPathComponent("package.json")
        let pubspec = root.appendingPathComponent("pubspec.yaml")
        let packageText = (try? String(contentsOf: packageJSON, encoding: .utf8)) ?? ""
        let pubspecText = (try? String(contentsOf: pubspec, encoding: .utf8)) ?? ""
        let swiftTexts = files.filter { $0.relativePath.hasSuffix(".swift") }
            .prefix(50)
            .compactMap { try? String(contentsOf: URL(fileURLWithPath: $0.absolutePath), encoding: .utf8) }
            .joined(separator: "\n")

        let framework: ImportFramework
        if swiftTexts.contains("import SwiftUI") {
            framework = .swiftUI
        } else if swiftTexts.contains("import UIKit") {
            framework = .uiKit
        } else if swiftTexts.contains("import AppKit") {
            framework = .appKit
        } else if packageText.contains("react-native") {
            framework = .reactNative
        } else if packageText.contains("\"electron\"") || fm.fileExists(atPath: root.appendingPathComponent("main.js").path) || fm.fileExists(atPath: root.appendingPathComponent("main.ts").path) {
            framework = .electron
        } else if packageText.contains("\"react\"") || files.contains(where: { $0.relativePath.hasSuffix(".jsx") || $0.relativePath.hasSuffix(".tsx") }) {
            framework = .react
        } else if pubspecText.contains("flutter:") {
            framework = .flutter
        } else if containsWebFiles(root: root) {
            framework = .htmlCSS
        } else {
            framework = .unknown
        }

        let candidates = candidates(for: framework, root: root)
        let state = implementationState(for: framework, candidates: candidates)
        let warnings = warnings(for: framework, candidates: candidates, state: state)
        return ImportProjectSummary(
            rootPath: root.path,
            framework: framework,
            implementationState: state,
            rating: rating(for: framework, candidates: candidates, state: state),
            fileCount: files.count,
            screenCount: candidates.filter { !$0.isPreviewOnly }.count,
            componentCount: componentCount(for: framework, files: files, candidates: candidates),
            warnings: warnings,
            candidates: candidates)
    }

    private func candidates(for framework: ImportFramework, root: URL) -> [ExistingUIImport.Candidate] {
        switch framework {
        case .swiftUI:
            return ExistingUIImport.scanRepository(root)
        case .react, .electron, .htmlCSS:
            return WebUIImport.scanRepository(root, framework: framework)
        case .uiKit, .appKit, .reactNative, .flutter, .unknown:
            return []
        }
    }

    private func implementationState(for framework: ImportFramework,
                                     candidates: [ExistingUIImport.Candidate]) -> ImplementationState {
        if framework == .unknown { return .unsupported }
        if framework == .swiftUI { return .implemented }
        if [.react, .electron, .htmlCSS].contains(framework) {
            return candidates.isEmpty ? .foundationOnly : .implemented
        }
        return .comingSoon
    }

    private func componentCount(for framework: ImportFramework, files: [RepositoryFile],
                                candidates: [ExistingUIImport.Candidate]) -> Int {
        if framework == .swiftUI {
            return files.filter { $0.role == .swiftUIView }.flatMap(\.viewNames).count
        }
        if [.react, .electron, .htmlCSS].contains(framework) {
            return candidates.reduce(0) { $0 + $1.supportedElementCount }
        }
        return 0
    }

    private func containsWebFiles(root: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return false }
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            if ["html", "css", "js"].contains(ext) { return true }
        }
        return false
    }

    private func rating(for framework: ImportFramework, candidates: [ExistingUIImport.Candidate], state: ImplementationState) -> ImportCompatibilityRating {
        if framework == .swiftUI, !candidates.isEmpty { return .green }
        if [.react, .electron, .htmlCSS].contains(framework), state == .implemented, !candidates.isEmpty { return .yellow }
        if state == .foundationOnly { return .yellow }
        return .red
    }

    private func warnings(for framework: ImportFramework, candidates: [ExistingUIImport.Candidate], state: ImplementationState) -> [String] {
        if framework == .swiftUI {
            return candidates.isEmpty ? ["SwiftUI detected, but no importable View structs were found."] : []
        }
        if state == .foundationOnly {
            return ["\(framework.displayName) detection is available; layer import adapter is foundation-only in this build."]
        }
        if [.react, .electron, .htmlCSS].contains(framework), state == .implemented {
            return ["\(framework.displayName) static layer import is available for discovered DOM/JSX screens. Scripts, CSS cascade, and runtime state remain source-owned."]
        }
        if state == .comingSoon {
            return ["\(framework.displayName) import is registered as coming soon."]
        }
        return ["Unsupported or unknown project type."]
    }
}
