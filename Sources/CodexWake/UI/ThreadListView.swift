import AppKit
import SwiftUI

struct ThreadListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pendingTrashThread: CodexThread?

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
                            Label("Repair Index", systemImage: "wrench.and.screwdriver")
                        }
                        .disabled(model.isDemoMode || model.isLoading || !thread.needsRepair)

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

                        Button(role: .destructive) {
                            pendingTrashThread = thread
                        } label: {
                            Label("Move to Trash", systemImage: "trash")
                        }
                        .disabled(model.isLoading)
                    }
                }
            }
            .listStyle(.plain)
        }
        .alert(
            "Repair complete",
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
        .alert("Move chat to Trash?", isPresented: isTrashThreadConfirmationPresented) {
            Button("Move to Trash", role: .destructive) {
                guard let thread = pendingTrashThread else { return }
                model.selectThread(thread)
                pendingTrashThread = nil
                Task { await model.moveSelectedThreadToTrash() }
            }
            Button("Cancel", role: .cancel) {
                pendingTrashThread = nil
            }
        } message: {
            Text("This moves the chat JSONL file to macOS Trash when it exists, removes the chat from Codex metadata, and creates safety backups for local state files first.")
        }
        .alert(
            "Move to Trash complete",
            isPresented: Binding(
                get: { model.batchTrashSuccessMessage != nil },
                set: { if !$0 { model.batchTrashSuccessMessage = nil } }
            )
        ) {
            Button("OK") {
                model.batchTrashSuccessMessage = nil
            }
        } message: {
            Text(model.batchTrashSuccessMessage ?? "")
        }
    }

    private var isTrashThreadConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingTrashThread != nil },
            set: { isPresented in
                if !isPresented {
                    pendingTrashThread = nil
                }
            }
        )
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
    @State private var isRepairConfirmationPresented = false
    @State private var isTrashConfirmationPresented = false

    var body: some View {
        HStack(spacing: 8) {
            Text("\(model.selectedThreadIDs.count) selected")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                isRepairConfirmationPresented = true
            } label: {
                Label("Repair Index", systemImage: "wrench.and.screwdriver")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isDemoMode || model.isLoading || model.selectedRepairableCount == 0)
            .help("Repair selected chats missing from session_index.jsonl")

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

            Button(role: .destructive) {
                isTrashConfirmationPresented = true
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(model.isLoading || model.selectedThreadIDs.isEmpty)
            .help("Move selected chat files to macOS Trash and remove them from Codex metadata")

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
        .background(WakeColors.reportBackground(.accentColor), in: RoundedRectangle(cornerRadius: 8))
        .alert("Repair \(model.selectedRepairableCount) selected chats?", isPresented: $isRepairConfirmationPresented) {
            Button("Repair Index") {
                Task { await model.wakeSelectedThreads() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Codex Wake will refresh Codex metadata for selected chats missing from session_index.jsonl and create backups for each operation. \(model.selectedRepairSkippedCount) already available, archived, or missing chats will be skipped.")
        }
        .alert("Move \(model.selectedThreadIDs.count) selected chats to Trash?", isPresented: $isTrashConfirmationPresented) {
            Button("Move to Trash", role: .destructive) {
                Task { await model.moveSelectedThreadsToTrash() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Codex Wake will move existing chat JSONL files to macOS Trash, remove selected chats from Codex metadata, and create safety backups for local state files first. Missing chat files will be cleaned from metadata only.")
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
        if isSelected { return WakeColors.selectionBackground(.accentColor) }
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
            .background(WakeColors.selectionBackground(color), in: Capsule())
            .foregroundStyle(color)
            .help(helpText)
    }

    private var color: Color {
        if thread.archived || !thread.fileExists { return .red }
        if thread.needsRepair { return .orange }
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
            return "This thread is missing from session_index.jsonl. Repair Index refreshes Codex metadata after creating backups."
        }
        return "This thread is available in Codex metadata."
    }
}
