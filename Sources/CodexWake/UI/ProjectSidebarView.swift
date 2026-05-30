import SwiftUI

struct ProjectSidebarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isBackupManagerPresented = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Codex Wake")
                    .font(.headline)
                Spacer()
                Button {
                    isBackupManagerPresented = true
                } label: {
                    Image(systemName: "archivebox")
                }
                .buttonStyle(.borderless)
                .help("Manage backups")

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

            Divider()

            List(selection: $model.selectedProjectID) {
                ForEach(model.projects) { project in
                    ProjectRow(project: project)
                        .tag(project.id)
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color(white: 0.94))
        .sheet(isPresented: $isBackupManagerPresented) {
            BackupManagerView()
                .environmentObject(model)
        }
    }
}

private struct ProjectRow: View {
    let project: ProjectSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(project.name)
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
