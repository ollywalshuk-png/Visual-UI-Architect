import SwiftUI
import BuildIntelligenceEngine

/// Build intelligence panel: toolchain summary, the build pipeline stages,
/// the exact repeatable build command, and configuration diagnostics — so
/// build state is visible and failures are explainable, never mysterious.
struct BuildDiagnosticsView: View {
    @EnvironmentObject var store: DocumentStore
    @Environment(\.dismiss) private var dismiss
    @State private var kind: BuildKind = .localDevelopment

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Build Diagnostics", systemImage: "hammer")
                    .font(.headline)
                Spacer()
                Picker("", selection: $kind) {
                    ForEach(BuildKind.allCases) { Text($0.displayName).tag($0) }
                }
                .frame(width: 180)
                .onChange(of: kind) { _, newKind in
                    store.refreshBuildContext(kind: newKind)
                }
                Button("Refresh") { store.refreshBuildContext(kind: kind) }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()

            if let ctx = store.buildContext {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        contextSection(ctx)
                        pipelineSection
                        diagnosticsSection(ctx)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "No Repository Open",
                    systemImage: "hammer",
                    description: Text("Open a repository (sidebar ▸ Repository) to inspect its build context."))
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(minWidth: 560, minHeight: 460)
        .onAppear { store.refreshBuildContext(kind: kind) }
    }

    private func contextSection(_ ctx: BuildContext) -> some View {
        GroupBox("Build Context") {
            VStack(alignment: .leading, spacing: 6) {
                row("Working directory", ctx.workingDirectory.path)
                row("Command", ctx.commandLine).fontDesign(.monospaced)
                row("Configuration", ctx.kind.configuration)
                row("Swift", ctx.toolchain.swiftVersion ?? "unknown")
                row("Toolchain", ctx.toolchain.commandLineToolsOnly
                    ? "Command Line Tools only (no xcodebuild / XCTest / #Preview)"
                    : "Full Xcode")
                row("Package.swift", ctx.packageManifest != nil ? "found" : "missing")
                row("Package.resolved", ctx.packageResolved != nil ? "present" : "missing")
                row("Build cache (.build)", ctx.hasBuildCache ? "present" : "cold")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pipelineSection: some View {
        GroupBox("Pipeline") {
            HStack(spacing: 6) {
                ForEach(BuildStage.pipeline) { stage in
                    Text(stage.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    if stage != BuildStage.pipeline.last {
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func diagnosticsSection(_ ctx: BuildContext) -> some View {
        GroupBox("Diagnostics (\(ctx.diagnostics.count))") {
            if ctx.diagnostics.isEmpty {
                Label("No build configuration issues detected.", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ctx.diagnostics) { d in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: icon(d.severity))
                                .foregroundStyle(color(d.severity))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.message)
                                if let s = d.suggestion {
                                    Text(s).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 160, alignment: .leading)
            Text(value).textSelection(.enabled)
        }
        .font(.callout)
    }

    private func icon(_ s: BuildDiagnostic.Severity) -> String {
        switch s {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }

    private func color(_ s: BuildDiagnostic.Severity) -> Color {
        switch s {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}
