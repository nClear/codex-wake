import SwiftUI

struct BackupTrashListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isEmptyTrashConfirmationPresented = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Trash", systemImage: "trash")
                        .font(.headline)
                    Spacer()
                    Text("\(model.backupTrash.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Text(model.backupTrashTotalSizeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        isEmptyTrashConfirmationPresented = true
                    } label: {
                        Label("Empty Trash", systemImage: "trash.slash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.backupTrash.isEmpty)
                }
            }
            .padding(12)

            Divider()

            if model.backupTrash.isEmpty {
                ContentUnavailableView("App trash is empty", systemImage: "trash")
            } else {
                List(selection: $model.selectedTrashBackupID) {
                    ForEach(model.backupTrash) { backup in
                        TrashBackupRow(backup: backup)
                            .tag(backup.id as String?)
                            .onTapGesture { model.selectedTrashBackupID = backup.id }
                    }
                }
                .listStyle(.plain)
            }
        }
        .alert("Empty backup trash?", isPresented: $isEmptyTrashConfirmationPresented) {
            Button("Empty Trash", role: .destructive) {
                Task { await model.emptyBackupTrash() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \(model.backupTrash.count) backup files from Codex Wake's app trash. You will not be able to restore these backups after this action.")
        }
    }
}

private struct TrashBackupRow: View {
    let backup: BackupFile

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(backup.kind.label, systemImage: backup.kind.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: backup.size, countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(backup.originalName)
                .font(.caption)
                .lineLimit(1)

            HStack(spacing: 8) {
                Label(WakeDates.display(backup.createdAt ?? backup.modifiedAt), systemImage: "clock")
                Text("in app trash")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text(backup.directory)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
    }
}
