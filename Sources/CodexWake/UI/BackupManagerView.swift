import SwiftUI

struct BackupManagerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDeleteSelected = false
    @State private var isConfirmingDeleteAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if model.isLoadingBackups && model.backups.isEmpty {
                ProgressView("Scanning backups...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.backups.isEmpty {
                ContentUnavailableView("No backups found", systemImage: "archivebox")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                backupList
            }

            Divider()
            footer
        }
        .frame(width: 760, height: 520)
        .liquidGlassBackground
        .task {
            await model.refreshBackups()
        }
        .alert("Delete selected backups?", isPresented: $isConfirmingDeleteSelected) {
            Button("Delete", role: .destructive) {
                Task { await model.deleteSelectedBackups() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(model.selectedBackupIDs.count) backup files will be removed.")
        }
        .alert("Delete all backups?", isPresented: $isConfirmingDeleteAll) {
            Button("Delete All", role: .destructive) {
                Task { await model.deleteAllBackups() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(model.backups.count) backup files using \(model.backupSizeLabel) will be removed.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Backups")
                    .font(.title3.weight(.semibold))
                Text("\(model.backups.count) files · \(model.backupSizeLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await model.refreshBackups() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .liquidGlassButtonStyle()
            .disabled(model.isLoadingBackups)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .liquidGlassButtonStyle()
            .help("Close")
        }
        .padding(16)
        .liquidGlassContainer(spacing: 10)
    }

    private var backupList: some View {
        Table(model.backups, selection: $model.selectedBackupIDs) {
            TableColumn("Original") { backup in
                VStack(alignment: .leading, spacing: 3) {
                    Text(backup.originalName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(backup.directory)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .width(min: 260, ideal: 320)

            TableColumn("Backup Time") { backup in
                Text(backup.stamp)
                    .font(.caption.monospaced())
            }
            .width(150)

            TableColumn("Modified") { backup in
                Text(WakeDates.display(backup.modifiedAt))
                    .font(.caption)
            }
            .width(150)

            TableColumn("Size") { backup in
                Text(backup.sizeLabel)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(80)
        }
        .contextMenu {
            Button {
                model.revealSelectedBackupsInFinder()
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            .disabled(model.selectedBackupIDs.isEmpty || model.isDemoMode)

            Button {
                model.copySelectedBackupPaths()
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
            .disabled(model.selectedBackupIDs.isEmpty)

            Divider()

            Button(role: .destructive) {
                isConfirmingDeleteSelected = true
            } label: {
                Label("Delete Selected", systemImage: "trash")
            }
            .disabled(model.selectedBackupIDs.isEmpty)
        }
        .scrollContentBackground(.hidden)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.selectedBackupIDs.isEmpty {
                Text("Select backups to reveal, copy, or delete.")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(model.selectedBackupIDs.count) selected · \(model.selectedBackupSizeLabel)")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.revealSelectedBackupsInFinder()
            } label: {
                Label("Reveal", systemImage: "folder")
            }
            .disabled(model.selectedBackupIDs.isEmpty || model.isDemoMode)

            Button {
                model.copySelectedBackupPaths()
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
            .disabled(model.selectedBackupIDs.isEmpty)

            Button(role: .destructive) {
                isConfirmingDeleteSelected = true
            } label: {
                Label("Delete Selected", systemImage: "trash")
            }
            .disabled(model.selectedBackupIDs.isEmpty || model.isLoadingBackups)

            Button(role: .destructive) {
                isConfirmingDeleteAll = true
            } label: {
                Label("Delete All", systemImage: "trash.slash")
            }
            .disabled(model.backups.isEmpty || model.isLoadingBackups)
        }
        .font(.caption)
        .padding(12)
        .liquidGlassContainer(spacing: 10)
    }
}
