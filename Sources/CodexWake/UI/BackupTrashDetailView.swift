import SwiftUI

struct BackupTrashDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isRestoreConfirmationPresented = false
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        Group {
            if let thread = model.selectedTrashThread {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        threadHeader(thread)
                        threadMetadata(thread)
                        threadActions
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let backup = model.selectedTrashBackup {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(backup)
                        metadata(backup)
                        actions
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("Select a trashed backup", systemImage: "trash")
            }
        }
        .alert("Restore this chat?", isPresented: $isRestoreConfirmationPresented) {
            Button("Restore Chat") {
                Task { await model.restoreSelectedTrashThread() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores the chat JSONL file and re-registers the saved Codex metadata from the trash manifest.")
        }
        .alert("Delete this trashed chat permanently?", isPresented: $isDeleteConfirmationPresented) {
            Button("Delete Permanently", role: .destructive) {
                Task { await model.deleteSelectedTrashThreadPermanently() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the trashed chat file and its restore manifest from Codex Keeper's app trash.")
        }
    }

    private func threadHeader(_ thread: TrashedThread) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Trashed Chat", systemImage: "text.bubble")
                .font(.title2.weight(.semibold))
            Text(thread.title)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func threadMetadata(_ thread: TrashedThread) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            row("Trashed", WakeDates.display(thread.trashedAt))
            row("Size", ByteCountFormatter.string(fromByteCount: thread.size, countStyle: .file))
            row("Project", thread.cwd)
            row("Original path", thread.originalPath)
            row("Trash path", thread.trashPath ?? "metadata only")
            row("Manifest", thread.manifestPath)
            row("Original exists", thread.originalExists ? "yes" : "no")
        }
        .font(.system(size: 12))
        .textSelection(.enabled)
    }

    private var threadActions: some View {
        HStack(spacing: 10) {
            Button {
                isRestoreConfirmationPresented = true
            } label: {
                Label("Restore Chat", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.borderedProminent)

            Button {
                model.revealSelectedTrashThreadInFinder()
            } label: {
                Label("Reveal", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .disabled(model.isDemoMode)

            Button {
                model.copySelectedTrashThreadPath()
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            Button {
                model.copySelectedTrashThreadOriginalPath()
            } label: {
                Label("Copy Original", systemImage: "arrowshape.turn.up.left")
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                isDeleteConfirmationPresented = true
            } label: {
                Label("Delete Permanently", systemImage: "trash.slash")
            }
            .buttonStyle(.bordered)
        }
    }

    private func header(_ backup: BackupFile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Trashed \(backup.kind.label)", systemImage: "trash")
                .font(.title2.weight(.semibold))
            Text(backup.originalName)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func metadata(_ backup: BackupFile) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            row("Created", WakeDates.display(backup.createdAt))
            row("Modified", WakeDates.display(backup.modifiedAt))
            row("Size", ByteCountFormatter.string(fromByteCount: backup.size, countStyle: .file))
            row("Original path", backup.originalPath)
            row("Trash path", backup.backupPath)
            row("Stamp", backup.stamp)
        }
        .font(.system(size: 12))
        .textSelection(.enabled)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                model.revealSelectedTrashBackupInFinder()
            } label: {
                Label("Reveal", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .disabled(model.isDemoMode)

            Button {
                model.copySelectedTrashBackupPath()
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            Button {
                model.copySelectedTrashBackupOriginalPath()
            } label: {
                Label("Copy Original", systemImage: "arrowshape.turn.up.left")
            }
            .buttonStyle(.bordered)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(4)
        }
    }
}
