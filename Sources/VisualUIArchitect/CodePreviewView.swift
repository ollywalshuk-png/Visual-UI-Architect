import SwiftUI
import VUACore
import ValidationEngine

/// Shows generated source for the current document with a copy action and a
/// pre-flight validation gate (the safe-commit principle, surfaced in the UI).
struct CodePreviewView: View {
    @EnvironmentObject var store: DocumentStore
    @Environment(\.dismiss) private var dismiss
    @State private var code: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Generated \(store.document.codeGenTarget.displayName)", systemImage: "curlybraces")
                    .font(.headline)
                Spacer()
                if store.validation.hasErrors {
                    Label("\(store.validation.errorCount) blocking error(s)", systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red).font(.callout)
                } else {
                    Label("Validation passed", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green).font(.callout)
                }
            }
            .padding()
            Divider()

            ScrollView {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }

            Divider()
            HStack {
                Button {
                    #if canImport(AppKit)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    #endif
                } label: { Label("Copy", systemImage: "doc.on.doc") }

                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 480)
        .onAppear { code = store.generateCode() }
    }
}
