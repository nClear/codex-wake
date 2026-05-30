import SwiftUI

struct ThreadListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isMoveSheetPresented = false
    @State private var rangeAnchorID: String?

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

                if model.selectedThreadCount > 1 {
                    selectionToolbar
                }
            }
            .padding(12)

            Divider()

            List {
                ForEach(model.filteredThreads) { thread in
                    ThreadRow(thread: thread, isSelected: model.selectedThreadIDs.contains(thread.id))
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowSeparator(.hidden)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            select(thread)
                        }
                        .contextMenu {
                            ThreadContextMenu(
                                thread: thread,
                                targetIDs: contextTargetIDs(for: thread),
                                isMoveSheetPresented: $isMoveSheetPresented
                            )
                            .environmentObject(model)
                        }
                }
            }
            .listStyle(.plain)
        }
        .sheet(isPresented: $isMoveSheetPresented) {
            MoveThreadSheet(isPresented: $isMoveSheetPresented)
                .environmentObject(model)
        }
    }

    private var selectionToolbar: some View {
        HStack(spacing: 8) {
            Text("\(model.selectedThreadCount) selected")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .leading)

            Button {
                Task { await model.wakeSelectedThreads() }
            } label: {
                Label("Wake", systemImage: "alarm")
            }
            .buttonStyle(.bordered)
            .disabled(model.isLoading || !model.canOperateOnSelectedThreads)

            Button {
                isMoveSheetPresented = true
            } label: {
                Label("Move", systemImage: "arrow.right.folder")
            }
            .buttonStyle(.bordered)
            .disabled(model.isLoading || model.moveTargetProjects.isEmpty)

            Button {
                model.revealSelectedInFinder()
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.bordered)
            .disabled(model.isDemoMode)
            .help("Reveal selected chats in Finder")

            Button {
                model.copySelectedPath()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .disabled(model.isDemoMode)
            .help("Copy selected chat paths")

            Spacer()
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func contextTargetIDs(for thread: CodexThread) -> Set<String> {
        model.selectedThreadIDs.contains(thread.id) ? model.selectedThreadIDs : [thread.id]
    }

    private func select(_ thread: CodexThread) {
        let event = NSApp.currentEvent
        let modifiers = event?.modifierFlags ?? []
        let isCommand = modifiers.contains(.command)
        let isShift = modifiers.contains(.shift)

        if isShift, let rangeSelection = rangeSelection(to: thread.id) {
            model.updateThreadSelection(rangeSelection, preferredID: thread.id)
            return
        }

        if isCommand {
            var next = model.selectedThreadIDs
            if next.contains(thread.id) {
                next.remove(thread.id)
            } else {
                next.insert(thread.id)
            }
            if next.isEmpty {
                next.insert(thread.id)
            }
            rangeAnchorID = thread.id
            model.updateThreadSelection(next, preferredID: thread.id)
            return
        }

        rangeAnchorID = thread.id
        model.updateThreadSelection([thread.id], preferredID: thread.id)
    }

    private func rangeSelection(to threadID: String) -> Set<String>? {
        let anchor = rangeAnchorID ?? model.selectedThreadID ?? model.selectedThreadIDs.first
        guard let anchor,
              let anchorIndex = model.filteredThreads.firstIndex(where: { $0.id == anchor }),
              let targetIndex = model.filteredThreads.firstIndex(where: { $0.id == threadID })
        else { return nil }

        let bounds = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        return Set(model.filteredThreads[bounds].map(\.id))
    }
}

private struct ThreadContextMenu: View {
    @EnvironmentObject private var model: AppModel

    let thread: CodexThread
    let targetIDs: Set<String>
    @Binding var isMoveSheetPresented: Bool

    var body: some View {
        Button {
            model.focusContextSelection(on: thread)
            Task { await model.wakeThreads(ids: targetIDs) }
        } label: {
            Label(targetIDs.count > 1 ? "Wake Selected Chats" : "Wake Chat", systemImage: "alarm")
        }
        .disabled(model.isLoading)

        Button {
            model.focusContextSelection(on: thread)
            isMoveSheetPresented = true
        } label: {
            Label(targetIDs.count > 1 ? "Move Selected Chats..." : "Move Chat...", systemImage: "arrow.right.folder")
        }
        .disabled(model.isLoading || targetIDs.isEmpty)

        Divider()

        Button {
            model.focusContextSelection(on: thread)
            model.revealThreadsInFinder(ids: targetIDs)
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }
        .disabled(model.isDemoMode)

        Button {
            model.focusContextSelection(on: thread)
            model.copyThreadPaths(ids: targetIDs)
        } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
        }
        .disabled(model.isDemoMode)
    }
}

private struct ThreadRow: View {
    let thread: CodexThread
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(thread.shortTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(2)
                Spacer()
                StatusPill(text: thread.statusLabel, thread: thread)
            }

            Text(thread.cwd)
                .font(.caption2)
                .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Label(WakeDates.display(thread.updatedAt), systemImage: "clock")
                if thread.sessionIndexUpdatedAt == nil {
                    Label("no index", systemImage: "exclamationmark.triangle")
                }
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectionBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    private var selectionBackground: Color {
        isSelected ? Color.accentColor : Color.clear
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
