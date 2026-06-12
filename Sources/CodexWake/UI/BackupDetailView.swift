import SwiftUI

struct BackupDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isRestoreConfirmationPresented = false
    @State private var isMoveToTrashConfirmationPresented = false

    var body: some View {
        Group {
            if let backup = model.selectedBackup {
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
                ContentUnavailableView("Select a backup", systemImage: "archivebox")
            }
        }
    }

    private func header(_ backup: BackupFile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(backup.kind.label, systemImage: backup.kind.systemImage)
                .font(.title2.weight(.semibold))
            if let chatTitle = backup.chatTitle {
                Text(chatTitle)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)
                Text(backup.reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
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
            row("Reason", backup.reason)
            row("Original exists", backup.originalExists ? "yes" : "no")
            row("Original path", backup.originalPath)
            row("Backup path", backup.backupPath)
            row("Stamp", backup.stamp)
        }
        .font(.system(size: 12))
        .textSelection(.enabled)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                isRestoreConfirmationPresented = true
            } label: {
                Label("Restore Chat", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canRestoreSelectedBackup)
            .help(restoreHelp)

            Button {
                model.revealSelectedBackupInFinder()
            } label: {
                Label("Reveal", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .disabled(model.isDemoMode)

            Button {
                model.copySelectedBackupPath()
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            Button {
                model.copySelectedBackupOriginalPath()
            } label: {
                Label("Copy Original Path", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                isMoveToTrashConfirmationPresented = true
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(model.isDemoMode && model.selectedBackup == nil)
        }
        .alert("Restore this chat?", isPresented: $isRestoreConfirmationPresented) {
            Button("Restore Chat", role: .destructive) {
                Task { await model.restoreSelectedBackup() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(restoreConfirmationText)
        }
        .alert("Move backup to app trash?", isPresented: $isMoveToTrashConfirmationPresented) {
            Button("Move to Trash", role: .destructive) {
                Task { await model.moveSelectedBackupToTrash() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This moves the selected backup into Codex Keeper's app trash. It will not be permanently deleted until you empty the app trash.")
        }
    }

    private var canRestoreSelectedBackup: Bool {
        model.selectedBackup?.kind == .chatFile
    }

    private var restoreHelp: String {
        guard let backup = model.selectedBackup else { return "Select a chat file backup to restore" }
        if backup.kind == .chatFile {
            return "Restore this chat file backup over its original file. The selected restore point stays in Backups."
        }
        return "Restore is available for chat file backups only."
    }

    private var restoreConfirmationText: String {
        guard let backup = model.selectedBackup else {
            return "This will replace the current chat file with this restore point."
        }
        let title = backup.chatTitle ?? backup.originalName
        return "Restore \"\(title)\"?\n\nBackup reason: \(backup.reason).\n\nThis will replace the current chat with this restore point. Any messages written after this restore point will be removed. The selected restore point will stay in Backups."
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
