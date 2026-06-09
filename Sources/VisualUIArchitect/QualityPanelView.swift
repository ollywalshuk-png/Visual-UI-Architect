import SwiftUI
import UIQualityEngine

/// UI Quality panel: dimension scores with grades, the top fixes, and every
/// finding with its recommendation. Answers "is this a good interface?",
/// not just "does it build?".
struct QualityPanelView: View {
    @EnvironmentObject var store: DocumentStore
    @Environment(\.dismiss) private var dismiss
    @State private var report: QualityReport?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("UI Quality", systemImage: "gauge.with.needle")
                    .font(.headline)
                Spacer()
                Button("Re-assess") { report = store.assessQuality() }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()

            if let report {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        scoreStrip(report.scores)
                        if !report.topRecommendations.isEmpty {
                            GroupBox("Top fixes") {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(Array(report.topRecommendations.enumerated()), id: \.offset) { i, fix in
                                        Text("\(i + 1). \(fix)")
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        findings(report)
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 600, minHeight: 480)
        .onAppear { report = store.assessQuality() }
    }

    private func scoreStrip(_ scores: QualityScores) -> some View {
        HStack(spacing: 10) {
            scoreBadge("Overall", scores.overall)
            scoreBadge("Design", scores.designQuality)
            scoreBadge("Layout", scores.layoutQuality)
            scoreBadge("Calm", scores.visualNoise)
            scoreBadge("A11y", scores.accessibility)
            scoreBadge("Responsive", scores.responsiveQuality)
        }
    }

    private func scoreBadge(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text(QualityScores.grade(value)).font(.title2).bold()
                .foregroundStyle(value >= 80 ? .green : value >= 60 ? .orange : .red)
            Text("\(value)").font(.caption2).foregroundStyle(.secondary)
            Text(label).font(.caption)
        }
        .frame(width: 76, height: 64)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }

    private func findings(_ report: QualityReport) -> some View {
        GroupBox("Findings (\(report.issues.count))") {
            if report.issues.isEmpty {
                Label("No quality issues detected.", systemImage: "checkmark.seal")
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(report.issues.sorted { $0.severity > $1.severity }) { issue in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: issue.severity == .problem
                                  ? "exclamationmark.octagon" : "lightbulb")
                                .foregroundStyle(issue.severity == .problem ? .red : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(issue.dimension.rawValue)
                                        .font(.caption2).bold()
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                                    Text(issue.message)
                                }
                                Text(issue.recommendation).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if !issue.layerIDs.isEmpty {
                                Button("Select") { store.selection = Set(issue.layerIDs) }
                                    .buttonStyle(.link).font(.caption)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
