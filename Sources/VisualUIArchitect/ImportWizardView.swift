import SwiftUI
import AppKit
import ImportEngine
import RepositoryEngine

struct ImportWizardView: View {
    @EnvironmentObject var store: DocumentStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRoot: URL?
    @State private var summary: ImportProjectSummary?
    @State private var selectedCandidateID: ExistingUIImport.Candidate.ID?
    @State private var activeStep = WizardStep.selectProject

    private let coordinator = ImportCoordinator()

    private enum WizardStep: Int, CaseIterable {
        case selectProject = 1
        case frameworkDetection
        case importSummary
        case screenDiscovery
        case review
        case importStep

        var title: String {
            switch self {
            case .selectProject: return "Select Project"
            case .frameworkDetection: return "Framework"
            case .importSummary: return "Summary"
            case .screenDiscovery: return "Screens"
            case .review: return "Review"
            case .importStep: return "Import"
            }
        }
    }

    private var selectedCandidate: ExistingUIImport.Candidate? {
        summary?.candidates.first { $0.id == selectedCandidateID }
    }

    private var canImport: Bool {
        summary?.implementationState == .implemented && selectedCandidate != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                stepList
                    .frame(width: 190)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(minWidth: 780, minHeight: 540)
    }

    private var header: some View {
        HStack {
            Label("Import Wizard", systemImage: "square.and.arrow.down.on.square")
                .font(.headline)
            Spacer()
            if let selectedRoot {
                Text(selectedRoot.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Button { chooseProject() } label: { Label("Choose Project...", systemImage: "folder") }
        }
        .padding()
    }

    private var stepList: some View {
        List(WizardStep.allCases, id: \.self, selection: $activeStep) { step in
            HStack {
                Text("\(step.rawValue)")
                    .font(.caption.bold())
                    .frame(width: 22, height: 22)
                    .background(step.rawValue <= activeStep.rawValue ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12),
                                in: Circle())
                Text(step.title)
            }
            .tag(step)
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detail: some View {
        switch activeStep {
        case .selectProject:
            ContentUnavailableViewCompat(title: "Choose a Project",
                                         systemImage: "folder.badge.plus",
                                         description: "Select a local app or repo folder to detect its UI framework before importing.")
                .padding()
        case .frameworkDetection:
            frameworkDetail
        case .importSummary:
            summaryDetail
        case .screenDiscovery:
            screensDetail
        case .review:
            reviewDetail
        case .importStep:
            importDetail
        }
    }

    @ViewBuilder
    private var frameworkDetail: some View {
        if let summary {
            VStack(alignment: .leading, spacing: 14) {
                Label(summary.framework.displayName, systemImage: frameworkIcon(summary.framework))
                    .font(.title2.bold())
                ratingBadge(summary.rating)
                stateRow("Implementation", summary.implementationState.rawValue)
                stateRow("Files", "\(summary.fileCount)")
                warnings(summary.warnings)
                Spacer()
            }
            .padding()
        } else {
            emptyProjectMessage
        }
    }

    @ViewBuilder
    private var summaryDetail: some View {
        if let summary {
            VStack(alignment: .leading, spacing: 12) {
                Text("Import Summary").font(.title2.bold())
                HStack(spacing: 16) {
                    metric("Framework", summary.framework.displayName)
                    metric("Screens", "\(summary.screenCount)")
                    metric("Components", "\(summary.componentCount)")
                    metric("Files", "\(summary.fileCount)")
                }
                warnings(summary.warnings)
                Spacer()
            }
            .padding()
        } else {
            emptyProjectMessage
        }
    }

    @ViewBuilder
    private var screensDetail: some View {
        if let summary {
            VStack(alignment: .leading, spacing: 10) {
                Text("Screen Discovery").font(.title2.bold())
                if summary.candidates.isEmpty {
                    ContentUnavailableViewCompat(title: "No Importable Screens",
                                                 systemImage: "rectangle.dashed",
                                                 description: "This project type is detected, but no SwiftUI screen candidates are available yet.")
                } else {
                    List(selection: $selectedCandidateID) {
                        ForEach(summary.candidates) { candidate in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(candidate.viewName).fontWeight(.medium)
                                Text(candidate.filePath)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                HStack {
                                    Text("confidence \(Int(candidate.confidence * 100))%")
                                    Text(candidate.hasAnchors ? "anchored" : "auto-anchor on import")
                                    if candidate.isPreviewOnly { Text("preview") }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            .tag(candidate.id)
                        }
                    }
                }
                Spacer()
            }
            .padding()
        } else {
            emptyProjectMessage
        }
    }

    @ViewBuilder
    private var reviewDetail: some View {
        if let summary {
            VStack(alignment: .leading, spacing: 12) {
                Text("Review").font(.title2.bold())
                metric("Project", selectedRoot?.lastPathComponent ?? "None")
                metric("Framework", summary.framework.displayName)
                metric("Compatibility", summary.rating.rawValue.capitalized)
                if let selectedCandidate {
                    metric("Selected Screen", selectedCandidate.viewName)
                }
                warnings(summary.warnings)
                Spacer()
            }
            .padding()
        } else {
            emptyProjectMessage
        }
    }

    @ViewBuilder
    private var importDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import").font(.title2.bold())
            if canImport {
                Label("Ready to import the selected screen into editable canvas layers.",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if let summary {
                Label("\(summary.framework.displayName) import is not fully enabled in this build.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                warnings(summary.warnings)
            } else {
                emptyProjectMessage
            }
            Spacer()
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            if let summary {
                Label(summary.framework.displayName, systemImage: frameworkIcon(summary.framework))
                    .foregroundStyle(.secondary)
                ratingBadge(summary.rating)
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
            Button("Back") { activeStep = WizardStep(rawValue: max(1, activeStep.rawValue - 1)) ?? .selectProject }
                .disabled(activeStep == .selectProject)
            Button(activeStep == .importStep ? "Import" : "Next") {
                if activeStep == .importStep {
                    if let selectedCandidate, store.importExistingUI(selectedCandidate) { dismiss() }
                } else {
                    activeStep = WizardStep(rawValue: min(WizardStep.importStep.rawValue, activeStep.rawValue + 1)) ?? .importStep
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(activeStep == .importStep && !canImport)
        }
        .padding()
    }

    private var emptyProjectMessage: some View {
        ContentUnavailableViewCompat(title: "No Project Selected",
                                     systemImage: "folder",
                                     description: "Choose a local project folder to run framework detection.")
            .padding()
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose a project to import"
        if panel.runModal() == .OK, let url = panel.url {
            selectedRoot = url
            let detected = coordinator.summarize(root: url)
            summary = detected
            selectedCandidateID = detected.candidates.first(where: { !$0.isPreviewOnly })?.id ?? detected.candidates.first?.id
            activeStep = .frameworkDetection
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).fontWeight(.semibold).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stateRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.callout)
    }

    private func warnings(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func ratingBadge(_ rating: ImportCompatibilityRating) -> some View {
        Text(rating.rawValue.capitalized)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(ratingColor(rating).opacity(0.18), in: Capsule())
            .foregroundStyle(ratingColor(rating))
    }

    private func ratingColor(_ rating: ImportCompatibilityRating) -> Color {
        switch rating {
        case .green: return .green
        case .yellow: return .orange
        case .red: return .red
        }
    }

    private func frameworkIcon(_ framework: ImportFramework) -> String {
        switch framework {
        case .swiftUI, .uiKit, .appKit: return "swift"
        case .react, .reactNative: return "atom"
        case .electron: return "macwindow"
        case .htmlCSS: return "globe"
        case .flutter: return "diamond"
        case .unknown: return "questionmark.folder"
        }
    }
}
