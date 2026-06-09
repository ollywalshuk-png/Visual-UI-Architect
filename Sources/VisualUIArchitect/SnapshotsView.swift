import SwiftUI
import PersistenceEngine

/// Version snapshots browser — lists timestamped snapshots stored in the
/// `.vuaproj` bundle and restores any of them ("Time Machine" for UI edits).
struct SnapshotsView: View {
    @EnvironmentObject var store: DocumentStore
    @Environment(\.dismiss) private var dismiss
    @State private var snapshots: [SnapshotStore.Info] = []

    private let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .medium; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Version Snapshots", systemImage: "clock.arrow.circlepath").font(.headline)
                Spacer()
            }.padding()
            Divider()

            if store.documentURL == nil {
                ContentUnavailableViewCompat(
                    title: "Save First",
                    systemImage: "externaldrive.badge.questionmark",
                    description: "Snapshots are stored inside the .vuaproj bundle. Save the project to start capturing them.")
            } else if snapshots.isEmpty {
                ContentUnavailableViewCompat(
                    title: "No Snapshots Yet",
                    systemImage: "clock",
                    description: "A snapshot is captured automatically each time you save.")
            } else {
                List(snapshots) { snap in
                    HStack {
                        Image(systemName: "doc.badge.clock").foregroundStyle(.secondary)
                        Text(formatter.string(from: snap.date))
                        Spacer()
                        Button("Restore") {
                            store.restoreSnapshot(snap)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding()
        }
        .frame(minWidth: 460, minHeight: 380)
        .onAppear { snapshots = store.snapshots() }
    }
}
