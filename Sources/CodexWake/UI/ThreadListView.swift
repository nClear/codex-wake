import AppKit
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
                    Button {
                        model.runDeepSearch()
                    } label: {
                        Label("Deep Search", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isDeepSearching || model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                    .help("Deep search inside JSONL chat files")

                    if model.isDeepSearching {
                        Button {
                            model.cancelDeepSearch()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .help("Cancel deep search")
                    }
                }
                .padding(8)
                .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                if model.isSelectingThreads {
                    ThreadSelectionToolbar()
                } else {
                    ThreadSelectionEntryToolbar()
                }
            }
            .padding(12)

            Divider()

            List {
                ForEach(model.filteredThreads) { thread in
                    ThreadRow(
                        thread: thread,
                        isSelecting: model.isSelectingThreads,
                        isSelected: model.selectedThreadIDs.contains(thread.id),
                        isPrimary: model.selectedThreadID == thread.id
                    ) {
                        model.toggleThreadSelection(thread)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.handleThreadClick(
                            thread,
                            commandPressed: NSEvent.modifierFlags.contains(.command)
                        )
                    }
                    .contextMenu {
                        Button {
                            model.selectThread(thread)
                            Task { await model.wakeSelectedThread() }
                        } label: {
                            Label("Wake", systemImage: "alarm")
                        }
                        .disabled(model.isDemoMode || model.isLoading || thread.archived || !thread.fileExists)

                        Button {
                            model.selectThread(thread)
                        } label: {
                            Label("Select", systemImage: "text.bubble")
                        }

                        Button {
                            model.copyThreadPath(thread)
                        } label: {
                            Label("Copy Path", systemImage: "doc.on.doc")
                        }

                        Button {
                            model.revealThreadInFinder(thread)
                        } label: {
                            Label("Reveal", systemImage: "folder")
                        }
                        .disabled(model.isDemoMode)
                    }
                }
            }
            .listStyle(.plain)
        }
        .onChange(of: model.selectedThreadID) { _, newValue in
            guard !model.isSelectingThreads else { return }
            guard let id = newValue, let thread = model.filteredThreads.first(where: { $0.id == id }) else { return }
            model.selectThread(thread)
        }
        .alert(
            "Wake complete",
            isPresented: Binding(
                get: { model.batchWakeSuccessMessage != nil },
                set: { if !$0 { model.batchWakeSuccessMessage = nil } }
            )
        ) {
            Button("OK") {
                model.batchWakeSuccessMessage = nil
            }
        } message: {
            Text(model.batchWakeSuccessMessage ?? "")
        }
    }
}

private struct ThreadSelectionEntryToolbar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.startThreadSelection()
            } label: {
                Label("Multi-select chats", systemImage: "checklist")
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .frame(height: 36)
    }
}

private struct ThreadSelectionToolbar: View {
    @EnvironmentObject private var model: AppModel
    @State private var isWakeConfirmationPresented = false

    var body: some View {
        HStack(spacing: 8) {
            Text("\(model.selectedThreadIDs.count) selected")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                isWakeConfirmationPresented = true
            } label: {
                Label("Wake", systemImage: "alarm")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isDemoMode || model.isLoading || model.selectedWakeableCount == 0)
            .help("Wake selected chats")

            Button {
                model.copySelectedThreadPaths()
            } label: {
                Label("Copy Paths", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .disabled(model.selectedThreadIDs.isEmpty)

            Button {
                model.revealSelectedThreadsInFinder()
            } label: {
                Label("Reveal", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .disabled(model.isDemoMode || model.selectedThreadIDs.isEmpty)

            Button {
                model.cancelThreadSelection()
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
        }
        .padding(8)
        .frame(height: 36)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .alert("Wake \(model.selectedWakeableCount) selected chats?", isPresented: $isWakeConfirmationPresented) {
            Button("Wake") {
                Task { await model.wakeSelectedThreads() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Codex Wake will run the same single-chat Wake operation for each writable selected chat and create backups for each operation. \(model.selectedWakeSkippedCount) archived or missing chats will be skipped.")
        }
    }
}

private struct ThreadRow: View {
    let thread: CodexThread
    let isSelecting: Bool
    let isSelected: Bool
    let isPrimary: Bool
    let onToggleSelection: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isSelecting {
                Button {
                    onToggleSelection()
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(isSelected ? "Remove from selection" : "Add to selection")
                .padding(.top, 2)
            }

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
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.12) }
        if isPrimary { return Color.primary.opacity(0.05) }
        return .clear
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
            .help(helpText)
    }

    private var color: Color {
        if thread.archived || !thread.fileExists { return .red }
        if thread.needsWake { return .orange }
        return .green
    }

    private var helpText: String {
        if thread.archived {
            return "This thread is archived."
        }
        if !thread.fileExists {
            return "The chat file referenced by Codex metadata is missing on disk."
        }
        if !thread.isInSessionIndex {
            return "This thread is missing from session_index.jsonl. Wake updates Codex metadata so it can appear in the sidebar again."
        }
        if thread.needsWake {
            return "Codex may hide this thread from the sidebar because its latest message is older than one week. Wake updates its timestamp."
        }
        return "This thread is recent and present in Codex's session index."
    }
}
