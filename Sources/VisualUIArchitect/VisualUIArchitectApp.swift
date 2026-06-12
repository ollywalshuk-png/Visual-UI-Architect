import SwiftUI
import VUACore
import ControlBehaviourEngine

extension Notification.Name {
    /// Posted by the File ▸ Import Existing UI… command; MainWindow opens the sheet.
    static let vuaImportExistingUI = Notification.Name("vua.importExistingUI")
}

@main
struct VisualUIArchitectApp: App {
    @StateObject private var store = DocumentStore()
    @StateObject private var theme = ThemeSettings()

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(store)
                .environmentObject(theme)
                .preferredColorScheme(theme.theme.colorScheme)
                .tint(theme.accent)
                .frame(minWidth: 1100, minHeight: 720)
                // On launch: offer crash recovery if present, else auto-reopen
                // the last saved project. Start autosave either way.
                .task {
                    if store.pendingRecovery() == nil { store.autoReopenLast() }
                    store.startAutosave()
                }
        }
        .commands {
            EditorCommands(store: store)
            FileCommands(store: store)
        }
    }
}

/// Edit-menu commands: undo/redo, duplicate, delete, nudge.
struct EditorCommands: Commands {
    @ObservedObject var store: DocumentStore

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { store.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!store.canUndo || !store.canEditDocument)
            Button("Redo") { store.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!store.canRedo || !store.canEditDocument)
        }
        CommandGroup(after: .pasteboard) {
            Button("Cut") { store.cutSelection() }
                .keyboardShortcut("x", modifiers: .command)
                .disabled(store.selection.isEmpty || !store.canEditDocument)
            Button("Copy") { store.copySelection() }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(store.selection.isEmpty)
            Button("Paste") { store.paste() }
                .keyboardShortcut("v", modifiers: .command)
                .disabled(!store.canPaste || !store.canEditDocument)
            Button("Duplicate") { store.duplicateSelection() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(store.selection.isEmpty || !store.canEditDocument)
            Button("Delete") { store.deleteSelection() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(store.selection.isEmpty || !store.canEditDocument)
            Divider()
            Button("Select All") { store.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
            Button("Deselect All") { store.deselectAll() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Invert Selection") { store.invertSelection() }
        }
        CommandMenu("Arrange") {
            Button("Group") { store.groupSelection() }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(!store.canGroup || !store.canEditDocument)
            Button("Ungroup") { store.ungroupSelection() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!store.canUngroup || !store.canEditDocument)
            Divider()
            Button("Bring to Front") { store.bringSelectionToFront() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(store.selection.isEmpty || !store.canEditDocument)
            Button("Bring Forward") { store.bringSelectionForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(store.selection.isEmpty || !store.canEditDocument)
            Button("Send Backward") { store.sendSelectionBackward() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(store.selection.isEmpty || !store.canEditDocument)
            Button("Send to Back") { store.sendSelectionToBack() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(store.selection.isEmpty || !store.canEditDocument)
        }
        CommandMenu("Mode") {
            Button(store.editorMode == .build ? "Enter Test Mode" : "Return to Build Mode") {
                store.toggleEditorMode()
            }
            .keyboardShortcut("t", modifiers: .command)
            Button("Exit Active Test Interaction") {
                store.exitActivePreviewInteraction()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(!store.isTestMode)
            Button("Reset Preview Values") {
                store.resetPreviewValues()
            }
            .disabled(!store.isTestMode)
        }
    }
}

/// File-menu commands: New, Open, Open Recent, Save, Save As.
struct FileCommands: Commands {
    @ObservedObject var store: DocumentStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") { store.newDocument() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Open…") { store.openProject() }
                .keyboardShortcut("o", modifiers: .command)
            Divider()
            Button("Import Existing UI…") {
                NotificationCenter.default.post(name: .vuaImportExistingUI, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            Divider()
            Menu("Open Recent") {
                let recents = DocumentStore.recents.recents
                if recents.isEmpty {
                    Text("No Recent Documents").disabled(true)
                } else {
                    ForEach(recents, id: \.self) { url in
                        Button(url.deletingPathExtension().lastPathComponent) {
                            store.openProject(at: url)
                        }
                    }
                    Divider()
                    Button("Clear Menu") { DocumentStore.recents.clear() }
                }
            }
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { store.save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!store.isDirty && store.documentURL != nil)
            Button("Save As…") { _ = store.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button("Close") { store.requestClose() }
                .keyboardShortcut("w", modifiers: .command)
        }
    }
}
