import Foundation

/// What kind of continuation document to generate. Each mode reorders and
/// trims the sections for its audience, but every mode carries the safety
/// rules and recovery commands.
public enum HandoffMode: String, CaseIterable, Sendable, Identifiable {
    case fullProject
    case currentDocument
    case bugFix
    case nextPhase
    case export
    case aiModel
    case developer

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fullProject: return "Full Project"
        case .currentDocument: return "Current Document"
        case .bugFix: return "Bug Fix"
        case .nextPhase: return "Next Phase"
        case .export: return "Export"
        case .aiModel: return "AI Model"
        case .developer: return "Developer"
        }
    }
}

/// Everything the generator needs, captured as plain values so the output is
/// deterministic: same input → byte-identical handoff (diffable, testable).
public struct HandoffInput: Sendable {
    public var productMission: String
    public var repoPath: String?
    public var documentPath: String?
    public var branch: String?
    public var latestCommit: String?
    public var workingTreeDirty: Bool?
    public var buildStatus: String
    public var checkResult: String
    public var modules: [String]
    public var capabilities: [String]
    public var documentName: String
    public var layerCount: Int
    public var assetCount: Int
    public var targetDevice: String
    public var warnings: [String]
    public var knownLimitations: [String]
    public var roadmap: [String]
    public var nextRecommendedPhase: String
    public var generatedAt: String?

    public init(productMission: String = HandoffGenerator.defaultMission,
                repoPath: String? = nil,
                documentPath: String? = nil,
                branch: String? = nil,
                latestCommit: String? = nil,
                workingTreeDirty: Bool? = nil,
                buildStatus: String = "unknown — run `swift build`",
                checkResult: String = "unknown — run `swift run VUACheck`",
                modules: [String] = [],
                capabilities: [String] = [],
                documentName: String = "Untitled",
                layerCount: Int = 0,
                assetCount: Int = 0,
                targetDevice: String = "—",
                warnings: [String] = [],
                knownLimitations: [String] = [],
                roadmap: [String] = [],
                nextRecommendedPhase: String = "—",
                generatedAt: String? = nil) {
        self.productMission = productMission
        self.repoPath = repoPath
        self.documentPath = documentPath
        self.branch = branch
        self.latestCommit = latestCommit
        self.workingTreeDirty = workingTreeDirty
        self.buildStatus = buildStatus
        self.checkResult = checkResult
        self.modules = modules
        self.capabilities = capabilities
        self.documentName = documentName
        self.layerCount = layerCount
        self.assetCount = assetCount
        self.targetDevice = targetDevice
        self.warnings = warnings
        self.knownLimitations = knownLimitations
        self.roadmap = roadmap
        self.nextRecommendedPhase = nextRecommendedPhase
        self.generatedAt = generatedAt
    }
}

/// Generates a continuation HANDOFF.md so another AI model or developer can
/// pick the project up safely — current state, verified baseline, safety
/// rules, recovery commands, and what to do (and not do) next.
public struct HandoffGenerator: Sendable {

    public static let defaultMission = """
    Visual UI Architect is a professional, local-first, repository-aware visual \
    UI engineering platform for macOS. What the user edits visually must become \
    correct, buildable, reviewable SwiftUI in the target app or repository.
    """

    public static let safetyRules: [String] = [
        "Do not restart or regenerate the project — continue from the verified state below.",
        "Do not rewrite the architecture casually; major changes need a documented reason, migration, rollback and verification plan.",
        "Run `swift build` and `swift run VUACheck` before and after changes; never commit a failing build.",
        "Preserve source anchors (`.accessibilityIdentifier`) — they are the round-trip contract.",
        "Do not replace SwiftSyntax parsing with regex.",
        "Keep the app local-first: no cloud dependencies, no telemetry, no paid APIs.",
        "Do not delete modules without an equivalent, documented replacement.",
    ]

    public static let recoveryCommands: [String] = [
        "git status                  # confirm the working tree state",
        "git log --oneline -10       # confirm the baseline commit",
        "swift build                 # must be clean",
        "swift run VUACheck          # engine verification (no Xcode needed)",
        "./Scripts/make_app.sh       # rebuild the .app bundle",
        "git stash / git checkout .  # roll back uncommitted damage",
    ]

    public init() {}

    public func generate(_ input: HandoffInput, mode: HandoffMode = .fullProject) -> String {
        var s = ""
        func line(_ text: String = "") { s += text + "\n" }
        func section(_ title: String) { line(); line("## " + title); line() }

        line("# Visual UI Architect — \(mode.displayName) Handoff")
        if let at = input.generatedAt { line(); line("Generated: \(at)") }

        section("Product mission")
        line(input.productMission)

        section("Verified state")
        line("| Field | Value |")
        line("|---|---|")
        line("| Repository | \(input.repoPath ?? "—") |")
        line("| Document | \(input.documentPath ?? "unsaved") |")
        line("| Branch | \(input.branch ?? "—") |")
        line("| Latest commit | \(input.latestCommit ?? "—") |")
        line("| Working tree | \(input.workingTreeDirty.map { $0 ? "DIRTY — uncommitted changes" : "clean" } ?? "—") |")
        line("| Build | \(input.buildStatus) |")
        line("| Checks | \(input.checkResult) |")
        if input.workingTreeDirty == true {
            line()
            line("> ⚠️ The working tree is dirty. This handoff describes uncommitted state —")
            line("> commit or stash before structural work.")
        }

        if mode == .currentDocument || mode == .fullProject || mode == .export {
            section("Current document")
            line("- Name: \(input.documentName)")
            line("- Layers: \(input.layerCount)")
            line("- Assets: \(input.assetCount)")
            line("- Target device: \(input.targetDevice)")
        }

        if !input.modules.isEmpty {
            section("Architecture map (modules)")
            for m in input.modules.sorted() { line("- `\(m)`") }
        }

        if !input.capabilities.isEmpty && mode != .bugFix {
            section("Capabilities already built — do not rebuild")
            for cap in input.capabilities { line("- \(cap)") }
        }

        if !input.warnings.isEmpty {
            section("Current warnings")
            for w in input.warnings { line("- ⚠️ \(w)") }
        }

        if !input.knownLimitations.isEmpty {
            section("Known limitations")
            for l in input.knownLimitations { line("- \(l)") }
        }

        section("Safety rules (non-negotiable)")
        for rule in Self.safetyRules { line("- \(rule)") }

        section("Verification & recovery commands")
        line("```bash")
        for cmd in Self.recoveryCommands { line(cmd) }
        line("```")

        if !input.roadmap.isEmpty && (mode == .fullProject || mode == .nextPhase || mode == .aiModel || mode == .developer) {
            section("Roadmap")
            for item in input.roadmap { line("- \(item)") }
        }

        section("Next recommended work")
        line(input.nextRecommendedPhase)
        if mode == .bugFix {
            line()
            line("Scope: fix the bug described above ONLY. No refactors, no drive-by changes.")
        }

        section("Phase execution rule")
        line("Every phase must: start from a green baseline → add focused capability →")
        line("`swift build` → `swift run VUACheck` → rebuild the app bundle if relevant →")
        line("update README/ROADMAP → report changed files and limitations → commit only when green.")

        return s
    }
}
