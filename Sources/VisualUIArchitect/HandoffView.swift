import SwiftUI
import AppKit
import HandoffGeneratorEngine

/// Handoff generator panel: pick a mode, preview the generated HANDOFF.md,
/// copy it, or write it into the repository root.
struct HandoffView: View {
    @EnvironmentObject var store: DocumentStore
    @Environment(\.dismiss) private var dismiss
    @State private var mode: HandoffMode = .fullProject
    @State private var text: String = ""
    @State private var statusMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("AI / Developer Handoff", systemImage: "person.line.dotted.person")
                    .font(.headline)
                Spacer()
                Picker("Mode", selection: $mode) {
                    ForEach(HandoffMode.allCases) { Text($0.displayName).tag($0) }
                }
                .frame(width: 220)
                .onChange(of: mode) { _, m in text = store.generateHandoff(mode: m) }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()

            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }

            Divider()
            HStack {
                if let statusMessage { Text(statusMessage).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    statusMessage = "Copied to clipboard."
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                Button {
                    if let url = store.writeHandoff(mode: mode) {
                        statusMessage = "Wrote \(url.path)"
                    } else {
                        statusMessage = "No repository or saved document to write next to."
                    }
                } label: { Label("Write HANDOFF.md", systemImage: "square.and.arrow.down") }
            }
            .padding()
        }
        .frame(minWidth: 640, minHeight: 520)
        .onAppear { text = store.generateHandoff(mode: mode) }
    }
}
