import SwiftUI

struct ProjectSidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Codex Wake")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Picker("Project sort", selection: $model.projectSortMode) {
                Text("Recent").tag(ProjectSortMode.recent)
                Text("Name").tag(ProjectSortMode.name)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Divider()

            if !model.backups.isEmpty {
                Button {
                    model.showBackups()
                } label: {
                    BackupSidebarRow(
                        title: "Backups",
                        systemImage: "archivebox",
                        count: model.backups.count,
                        totalSize: model.backupTotalSizeText,
                        isSelected: model.selectedSection == .backups,
                        accentColor: .accentColor
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .help("View Codex Wake backup files")
            }

            if !model.backupTrash.isEmpty {
                Button {
                    model.showBackupTrash()
                } label: {
                    BackupSidebarRow(
                        title: "Trash",
                        systemImage: "trash",
                        count: model.backupTrash.count,
                        totalSize: model.backupTrashTotalSizeText,
                        isSelected: model.selectedSection == .backupTrash,
                        accentColor: .red
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                .help("View Codex Wake app trash")
            }

            List(selection: $model.selectedProjectID) {
                ForEach(model.projects) { project in
                    ProjectRow(project: project)
                        .tag(project.id)
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color(white: 0.94))
    }
}

private struct BackupSidebarRow: View {
    let title: String
    let systemImage: String
    let count: Int
    let totalSize: String
    let isSelected: Bool
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(count)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            HStack(spacing: 6) {
                Image(systemName: "internaldrive")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(totalSize)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(isSelected ? accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProjectRow: View {
    let project: ProjectSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(project.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(project.totalCount)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            HStack(spacing: 8) {
                Label("\(project.shownCount)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if project.hiddenCount > 0 {
                    Label("\(project.hiddenCount)", systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption2)
            .labelStyle(.titleAndIcon)

            if !project.path.isEmpty {
                Text(project.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}
