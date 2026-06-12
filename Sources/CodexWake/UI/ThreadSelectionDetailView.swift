import SwiftUI

struct ThreadSelectionDetailView: View {
    @EnvironmentObject private var model: AppModel

    private var selected: [CodexThread] {
        model.selectedThreads
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                summary
                actions
                selectedList
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(selected.count) chats selected")
                .font(.title2.weight(.semibold))
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            SummaryPill(title: "Available", value: selected.filter(\.isAvailable).count, color: .green)
            SummaryPill(title: "Repair", value: selected.filter(\.needsRepair).count, color: .orange)
            SummaryPill(title: "Archived", value: selected.filter(\.archived).count, color: .red)
            SummaryPill(title: "Missing", value: selected.filter { !$0.fileExists }.count, color: .red)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                model.copySelectedThreadPaths()
            } label: {
                Label("Copy Paths", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .disabled(selected.isEmpty)

            Button {
                model.revealSelectedThreadsInFinder()
            } label: {
                Label("Reveal", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .disabled(model.isDemoMode || selected.isEmpty)

            Button {
                model.cancelThreadSelection()
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
        }
    }

    private var selectedList: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(selected) { thread in
                SelectedThreadCard(thread: thread)
            }
        }
    }

}

private struct SummaryPill: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(WakeColors.reportBackground(color), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SelectedThreadCard: View {
    let thread: CodexThread

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(thread.shortTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                Spacer()
                Text(thread.statusLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(statusColor)
            }

            Text(thread.cwd)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Label(WakeDates.display(thread.updatedAt), systemImage: "clock")
                Text(thread.rolloutPath)
                    .lineLimit(1)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusColor: Color {
        if thread.archived || !thread.fileExists { return .red }
        if thread.needsRepair { return .orange }
        return .green
    }
}
