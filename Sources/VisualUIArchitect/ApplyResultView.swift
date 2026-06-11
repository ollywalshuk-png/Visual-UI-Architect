import SwiftUI
import RepositoryEngine

/// Presents the outcome of the safe-apply pipeline: which stage ran, the diff,
/// and (if run) build output. Commit is left to the user.
struct ApplyResultView: View {
    @Environment(\.dismiss) private var dismiss
    let result: SafeApplyResult

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(headline, systemImage: result.succeeded ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .foregroundStyle(result.succeeded ? .green : .red)
                    .font(.headline)
                Spacer()
            }
            .padding()
            Divider()

            stages.padding()

            if !result.plannedChanges.isEmpty || !result.unsupportedRegions.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    if !result.plannedChanges.isEmpty {
                        Text("Planned Anchors").font(.headline)
                        ForEach(result.plannedChanges, id: \.self) { change in
                            Text(change).font(.system(.caption, design: .monospaced))
                        }
                    }
                    if !result.unsupportedRegions.isEmpty {
                        Text("Preserved Regions").font(.headline).padding(.top, 4)
                        ForEach(result.unsupportedRegions, id: \.self) { region in
                            Label(region, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            if !result.diff.isEmpty {
                Divider()
                Text(result.previewOnly ? "Preview Diff" : "Diff").font(.headline).padding(.horizontal).padding(.top, 8)
                ScrollView { diffView.padding() }
            } else if result.buildRan && !result.buildPassed {
                Divider()
                Text("Build Output").font(.headline).padding(.horizontal).padding(.top, 8)
                ScrollView {
                    Text(result.buildOutput).font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading).padding()
                }
            } else {
                Spacer()
            }

            Divider()
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 460)
    }

    private var headline: String {
        switch result.blockedAt {
        case .validate: return "Blocked by validation"
        case .build: return "Blocked: build failed"
        case .some(let s): return "Blocked at \(s.rawValue)"
        case nil:
            if result.previewOnly { return result.diff.isEmpty ? "No changes" : "Preview ready" }
            return result.filesWritten.isEmpty ? "No changes" : "Applied to source"
        }
    }

    private var stages: some View {
        VStack(alignment: .leading, spacing: 6) {
            stageRow("Validate", passed: !result.validation.hasErrors,
                     detail: "\(result.validation.errorCount) error(s), \(result.validation.warningCount) warning(s)")
            stageRow(result.previewOnly ? "Preview" : "Write", passed: result.blockedAt != .validate,
                     detail: result.previewOnly
                        ? "\(result.plannedChanges.count) anchored change(s)"
                        : (result.filesWritten.isEmpty ? "no files" : result.filesWritten.joined(separator: ", ")))
            stageRow("Build", passed: !result.buildRan || result.buildPassed,
                     detail: result.buildRan ? (result.buildPassed ? "passed" : "failed") : "skipped")
            stageRow("Diff", passed: true, detail: result.diff.isEmpty ? "none" : "\(result.diff.split(separator: "\n").count) lines")
        }
    }

    private func stageRow(_ name: String, passed: Bool, detail: String) -> some View {
        HStack {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(passed ? .green : .red)
            Text(name).bold().frame(width: 80, alignment: .leading)
            Text(detail).foregroundStyle(.secondary)
        }
    }

    private var diffView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(result.diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                Text(String(line))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(color(for: String(line)))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func color(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .green }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .red }
        if line.hasPrefix("@@") { return .cyan }
        return .primary
    }
}
