import SwiftUI

struct BackupTrashDetailView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let backup = model.selectedTrashBackup {
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
