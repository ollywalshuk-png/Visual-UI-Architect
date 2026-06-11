import Foundation

public struct DeploymentReadinessReport: Sendable, Hashable {
    public struct Finding: Identifiable, Sendable, Hashable {
        public enum Severity: String, Sendable { case info, warning, blocker }
        public let id = UUID()
        public var severity: Severity
        public var message: String
    }

    public var findings: [Finding]
    public var ready: Bool { !findings.contains { $0.severity == .blocker } }
}

public enum DeploymentReadiness {
    public static func inspect(projectRoot: URL) -> DeploymentReadinessReport {
        let fm = FileManager.default
        var findings: [DeploymentReadinessReport.Finding] = []
        let package = projectRoot.appendingPathComponent("Package.swift")
        let script = projectRoot.appendingPathComponent("Scripts/make_app.sh")
        let app = projectRoot.appendingPathComponent("dist/Visual UI Architect.app")
        let binary = app.appendingPathComponent("Contents/MacOS/VisualUIArchitect")
        let info = app.appendingPathComponent("Contents/Info.plist")

        if !fm.fileExists(atPath: package.path) {
            findings.append(.init(severity: .blocker, message: "Package.swift is missing; SwiftPM release build cannot run."))
        }
        if !fm.fileExists(atPath: script.path) {
            findings.append(.init(severity: .blocker, message: "Scripts/make_app.sh is missing; app bundle assembly is unavailable."))
        } else if !fm.isExecutableFile(atPath: script.path) {
            findings.append(.init(severity: .warning, message: "Scripts/make_app.sh is not executable; run with zsh or restore execute permission."))
        }
        if fm.fileExists(atPath: app.path) {
            findings.append(.init(severity: .info, message: "Built app bundle exists at dist/Visual UI Architect.app."))
            if !fm.fileExists(atPath: info.path) {
                findings.append(.init(severity: .blocker, message: "App bundle is missing Contents/Info.plist."))
            }
            if !fm.isExecutableFile(atPath: binary.path) {
                findings.append(.init(severity: .blocker, message: "App bundle binary is missing execute permission."))
            }
        } else {
            findings.append(.init(severity: .warning, message: "No dist app bundle found yet; run zsh Scripts/make_app.sh."))
        }
        if findings.isEmpty {
            findings.append(.init(severity: .info, message: "Deployment readiness checks passed."))
        }
        return DeploymentReadinessReport(findings: findings)
    }
}
