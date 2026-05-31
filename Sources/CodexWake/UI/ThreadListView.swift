import SwiftUI

struct ThreadListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Text("Chats")
                        .font(.headline)
                    Spacer()
                    Text("\(model.filteredThreads.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search title, path, or chat text", text: $model.searchText)
                        .textFieldStyle(.plain)
                    if !model.searchText.isEmpty {
                        Button {
                            model.clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear search")
                    }
                }
                .padding(8)
                .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 8) {
                    Button {
                        model.runDeepSearch()
                    } label: {
                        Label("Deep Search", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isDeepSearching || model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                    .help("Search inside JSONL chat files")

                    if model.isDeepSearching {
                        Button {
                            model.cancelDeepSearch()
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()
                }
            }
            .padding(12)

            Divider()

            List(selection: $model.selectedThreadID) {
                ForEach(model.filteredThreads) { thread in
                    ThreadRow(thread: thread)
                        .tag(thread.id)
                        .onTapGesture { model.selectThread(thread) }
                }
            }
            .listStyle(.plain)
        }
        .onChange(of: model.selectedThreadID) { _, newValue in
            guard let id = newValue, let thread = model.filteredThreads.first(where: { $0.id == id }) else { return }
            model.selectThread(thread)
        }
    }
}

private struct ThreadRow: View {
    let thread: CodexThread

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(thread.shortTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                Spacer()
                Text(WakeDates.shortDate(thread.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                StatusPill(text: thread.statusLabel, thread: thread)
            }

            Text(thread.cwd)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Label(WakeDates.display(thread.updatedAt), systemImage: "clock")
                if thread.sessionIndexUpdatedAt == nil {
                    Label("no index", systemImage: "exclamationmark.triangle")
                }
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
    }
}

private struct StatusPill: View {
    let text: String
    let thread: CodexThread

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        if thread.archived || !thread.fileExists { return .red }
        if thread.needsWake { return .orange }
        return .green
    }
}
