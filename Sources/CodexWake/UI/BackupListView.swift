import SwiftUI

struct BackupListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Backups", systemImage: "archivebox")
                        .font(.headline)
                    Spacer()
                    Text("\(model.backups.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(model.backupTotalSizeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            if model.backups.isEmpty {
                ContentUnavailableView("No backups found", systemImage: "archivebox")
            } else {
                List(selection: $model.selectedBackupID) {
                    ForEach(model.backups) { backup in
                        BackupRow(backup: backup)
                            .tag(backup.id as String?)
                            .onTapGesture { model.selectedBackupID = backup.id }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

private struct BackupRow: View {
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

            if let chatTitle = backup.chatTitle {
                Text(chatTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(backup.reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(backup.originalName)
                    .font(.caption)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Label(WakeDates.display(backup.createdAt ?? backup.modifiedAt), systemImage: "clock")
                if !backup.originalExists {
                    Label("original missing", systemImage: "exclamationmark.triangle")
                }
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
