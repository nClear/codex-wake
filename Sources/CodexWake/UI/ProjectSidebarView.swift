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
