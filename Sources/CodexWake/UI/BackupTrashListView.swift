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
                    Text("\(model.trashItemCount)")
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
                    .disabled(model.trashItemCount == 0)
                }
            }
            .padding(12)

            Divider()

            if model.trashItemCount == 0 {
                ContentUnavailableView("App trash is empty", systemImage: "trash")
            } else {
                List {
                    if !model.threadTrash.isEmpty {
                        Section("Chats") {
                            ForEach(model.threadTrash) { thread in
                                TrashThreadRow(thread: thread, isSelected: model.selectedTrashThreadID == thread.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.selectTrashThread(thread) }
                            }
                        }
                    }

                    if !model.backupTrash.isEmpty {
                        Section("Backups") {
                            ForEach(model.backupTrash) { backup in
                                TrashBackupRow(backup: backup, isSelected: model.selectedTrashBackupID == backup.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.selectTrashBackup(backup) }
                            }
                        }
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
            Text("This permanently deletes \(model.threadTrash.count) trashed chats and \(model.backupTrash.count) backup files from Codex Keeper's app trash. You will not be able to restore them after this action.")
        }
    }
}

private struct TrashThreadRow: View {
    let thread: TrashedThread
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(thread.title, systemImage: "text.bubble")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: thread.size, countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Label(WakeDates.display(thread.trashedAt), systemImage: "clock")
                Text("trashed chat")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text(thread.cwd)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(isSelected ? WakeColors.selectionBackground(.accentColor) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TrashBackupRow: View {
    let backup: BackupFile
    let isSelected: Bool

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
        .background(isSelected ? WakeColors.selectionBackground(.accentColor) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }
}
