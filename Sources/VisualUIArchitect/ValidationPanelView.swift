import SwiftUI
import VUACore
import ValidationEngine

/// Shows accessibility/layout issues. Selecting an issue highlights its layers.
struct ValidationPanelView: View {
    @EnvironmentObject var store: DocumentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Validation", systemImage: "checkmark.shield")
                    .font(.headline)
                Spacer()
                summary
            }
            .padding(8)
            Divider()

            if store.validation.issues.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("No issues found.")
                }
                .padding(8)
            } else {
                List(store.validation.issues) { issue in
                    issueRow(issue)
                        .contentShape(Rectangle())
                        .onTapGesture { store.selection = Set(issue.layerIDs) }
                }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            if store.validation.errorCount > 0 {
                Label("\(store.validation.errorCount)", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
            if store.validation.warningCount > 0 {
                Label("\(store.validation.warningCount)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.callout)
    }

    private func issueRow(_ issue: ValidationIssue) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon(issue.severity)).foregroundStyle(color(issue.severity))
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.message).font(.callout)
                if let rec = issue.recommendation {
                    Text(rec).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(issue.category.rawValue).font(.caption2)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15), in: Capsule())
        }
        .padding(.vertical, 2)
    }

    private func icon(_ s: ValidationIssue.Severity) -> String {
        switch s {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle"
        }
    }

    private func color(_ s: ValidationIssue.Severity) -> Color {
        switch s {
        case .error: return .red
        case .warning: return .orange
        case .info: return .secondary
        }
    }
}
