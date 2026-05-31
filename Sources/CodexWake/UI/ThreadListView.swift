import SwiftUI

struct ThreadListView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var activePane: WakeFocusPane
    @State private var isMoveSheetPresented = false
    @State private var rangeAnchorID: String?
    @State private var visibleThreadIDs: Set<String> = []
    @State private var pendingThreadScrollAnchor: UnitPoint?
    @FocusState private var isSearchFocused: Bool

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
                        .focused($isSearchFocused)
                        .onSubmit {
                            setActivePane(.threads)
                            isSearchFocused = false
                        }
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
                .liquidGlassSurface(in: RoundedRectangle.compactLiquidGlass, interactive: true, fallbackMaterial: .thinMaterial)

                HStack(spacing: 8) {
                    Button {
                        model.runDeepSearch()
                    } label: {
                        Label("Deep Search", systemImage: "doc.text.magnifyingglass")
                    }
                    .liquidGlassButtonStyle()
                    .disabled(model.isDeepSearching || model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                    .help("Search inside JSONL chat files")

                    if model.isDeepSearching {
                        Button {
                            model.cancelDeepSearch()
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                        }
                        .liquidGlassButtonStyle()
                    }

                    Spacer()
                }
                .liquidGlassContainer(spacing: 8)

                if model.selectedThreadCount > 1 {
                    selectionToolbar
                }
            }
            .padding(12)

            Divider()

            GeometryReader { scrollGeometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        threadResults
                    }
                    .coordinateSpace(name: ThreadListCoordinateSpace.name)
                    .onPreferenceChange(ThreadRowFramePreferenceKey.self) { frames in
                        updateVisibleThreads(from: frames, viewportHeight: scrollGeometry.size.height)
                    }
                    .onChange(of: model.selectedThreadID) { _, selectedThreadID in
                        scrollToSelectedThread(selectedThreadID, proxy: proxy)
                    }
                }
            }
        }
        .sheet(isPresented: $isMoveSheetPresented) {
            MoveThreadSheet(isPresented: $isMoveSheetPresented)
                .environmentObject(model)
        }
        .onTapGesture {
            setActivePane(.threads)
        }
        .onReceive(NotificationCenter.default.publisher(for: .codexWakeFocusSearch)) { _ in
            setActivePane(.threads)
            isSearchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .codexWakeNavigateThread)) { notification in
            guard let action = notification.object as? WakeThreadNavigationAction else { return }
            navigateThread(action)
        }
    }

    @ViewBuilder
    private var threadResults: some View {
        if model.filteredThreads.isEmpty {
            emptyState
                .padding(28)
                .frame(maxWidth: .infinity, minHeight: 260)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(model.filteredThreads) { thread in
                    ThreadRow(
                        thread: thread,
                        isSelected: model.selectedThreadIDs.contains(thread.id),
                        query: model.searchText
                    )
                    .id(thread.id)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ThreadRowFramePreferenceKey.self,
                                value: [thread.id: geometry.frame(in: .named(ThreadListCoordinateSpace.name))]
                            )
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        select(thread)
                        setActivePane(.threads)
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
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
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
            .liquidGlassButtonStyle()
            .disabled(model.isLoading || !model.canOperateOnSelectedThreads)

            Button {
                isMoveSheetPresented = true
            } label: {
                Label("Move", systemImage: "folder.badge.plus")
            }
            .liquidGlassButtonStyle()
            .disabled(model.isLoading || model.moveTargetProjects.isEmpty)

            Button {
                model.revealSelectedInFinder()
            } label: {
                Image(systemName: "folder")
            }
            .liquidGlassButtonStyle()
            .disabled(model.isDemoMode)
            .help("Reveal selected chats in Finder")

            CopyFeedbackButton(
                text: model.selectedThreads.map(\.rolloutPath).joined(separator: "\n"),
                help: "Copy selected chat paths",
                usesPlainButtonStyle: false,
                normalForeground: .primary
            )
            .liquidGlassButtonStyle()
            .disabled(model.isDemoMode)
            .help("Copy selected chat paths")

            Spacer()
        }
        .padding(8)
        .liquidGlassSurface(in: RoundedRectangle.compactLiquidGlass, tint: .accentColor.opacity(0.14), interactive: true)
        .liquidGlassContainer(spacing: 8)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.secondary)
            Text(model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No chats" : "No matches")
                .font(.headline)
            if !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    model.clearSearch()
                    isSearchFocused = true
                } label: {
                    Label("Clear Search", systemImage: "xmark.circle")
                }
                .liquidGlassButtonStyle()
            }
        }
        .foregroundStyle(.secondary)
    }

    private func contextTargetIDs(for thread: CodexThread) -> Set<String> {
        model.selectedThreadIDs.contains(thread.id) ? model.selectedThreadIDs : [thread.id]
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

    private func setActivePane(_ pane: WakeFocusPane) {
        activePane = pane
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

    private func navigateThread(_ action: WakeThreadNavigationAction) {
        let didSelect: Bool
        switch action {
        case .offset(let offset):
            pendingThreadScrollAnchor = offset < 0 ? .top : .bottom
            didSelect = model.selectAdjacentThread(offset: offset, deferPreview: true)
        case .first:
            pendingThreadScrollAnchor = .top
            didSelect = model.selectThreadBoundary(.first, deferPreview: true)
        case .last:
            pendingThreadScrollAnchor = .bottom
            didSelect = model.selectThreadBoundary(.last, deferPreview: true)
        }

        if didSelect {
            rangeAnchorID = model.selectedThreadID
        } else {
            pendingThreadScrollAnchor = nil
        }
    }

    private func scrollToSelectedThread(_ threadID: String?, proxy: ScrollViewProxy) {
        guard let threadID else { return }
        guard !visibleThreadIDs.contains(threadID) else {
            pendingThreadScrollAnchor = nil
            return
        }
        let anchor = pendingThreadScrollAnchor ?? .center
        pendingThreadScrollAnchor = nil
        DispatchQueue.main.async {
            proxy.scrollTo(threadID, anchor: anchor)
        }
    }

    private func updateVisibleThreads(from frames: [String: CGRect], viewportHeight: CGFloat) {
        let nextVisibleIDs = Set(
            frames.compactMap { threadID, frame in
                frame.maxY > 0 && frame.minY < viewportHeight ? threadID : nil
            }
        )
        if nextVisibleIDs != visibleThreadIDs {
            visibleThreadIDs = nextVisibleIDs
        }
    }
}

private enum ThreadListCoordinateSpace {
    static let name = "thread-list-scroll"
}

private struct ThreadRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
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
            Label(targetIDs.count > 1 ? "Move Selected Chats..." : "Move Chat...", systemImage: "folder.badge.plus")
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
    let query: String
    @State private var isHovered = false

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                HighlightedText(
                    thread.shortTitle,
                    query: trimmedQuery,
                    font: .system(size: 13, weight: .medium),
                    defaultColor: isSelected ? .white : .primary,
                    highlightColor: isSelected ? .white : .accentColor,
                    lineLimit: 2
                )
                Spacer()
                StatusPill(text: thread.statusLabel, thread: thread, isSelected: isSelected)
            }

            HighlightedText(
                thread.cwd,
                query: trimmedQuery,
                font: .caption2,
                defaultColor: isSelected ? .white.opacity(0.82) : .secondary,
                highlightColor: isSelected ? .white : .accentColor,
                lineLimit: 1
            )

            if let searchSnippet {
                HighlightedText(
                    searchSnippet,
                    query: trimmedQuery,
                    font: .caption2,
                    defaultColor: isSelected ? .white.opacity(0.82) : .secondary,
                    highlightColor: isSelected ? .white : .accentColor,
                    lineLimit: 2
                )
            }

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
        .background(selectionBackground, in: RoundedRectangle.compactLiquidGlass)
        .modifier(ThreadRowGlassModifier(isActive: isSelected || isHovered, isSelected: isSelected))
        .onHover { isHovered = $0 }
    }

    private var selectionBackground: Color {
        isSelected ? Color.accentColor : Color.clear
    }

    private var searchSnippet: String? {
        guard !trimmedQuery.isEmpty else { return nil }
        for candidate in [thread.preview, thread.firstUserMessage, thread.rolloutPath, thread.id] {
            guard let snippet = candidate.matchSnippet(for: trimmedQuery, radius: 58) else { continue }
            if snippet != thread.shortTitle && snippet != thread.cwd {
                return snippet
            }
        }
        return nil
    }
}

private struct HighlightedText: View {
    let text: String
    let query: String
    let font: Font
    let defaultColor: Color
    let highlightColor: Color
    let lineLimit: Int

    init(
        _ text: String,
        query: String,
        font: Font,
        defaultColor: Color,
        highlightColor: Color,
        lineLimit: Int
    ) {
        self.text = text
        self.query = query
        self.font = font
        self.defaultColor = defaultColor
        self.highlightColor = highlightColor
        self.lineLimit = lineLimit
    }

    var body: some View {
        highlighted
            .font(font)
            .lineLimit(lineLimit)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var highlighted: Text {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return Text(text).foregroundColor(defaultColor)
        }

        var result = Text("")
        var remainder = text[...]
        var hasMatch = false

        while let range = remainder.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) {
            hasMatch = true
            if range.lowerBound > remainder.startIndex {
                result = result + Text(String(remainder[..<range.lowerBound])).foregroundColor(defaultColor)
            }
            result = result + Text(String(remainder[range])).foregroundColor(highlightColor).bold()
            remainder = remainder[range.upperBound...]
        }

        if !remainder.isEmpty {
            result = result + Text(String(remainder)).foregroundColor(defaultColor)
        }

        return hasMatch ? result : Text(text).foregroundColor(defaultColor)
    }
}

private struct ThreadRowGlassModifier: ViewModifier {
    let isActive: Bool
    let isSelected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content.liquidGlassSurface(
                in: RoundedRectangle.compactLiquidGlass,
                tint: isSelected ? .accentColor.opacity(0.24) : nil,
                interactive: true,
                fallbackMaterial: .thinMaterial
            )
        } else {
            content
        }
    }
}

private struct StatusPill: View {
    let text: String
    let thread: CodexThread
    let isSelected: Bool

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
            .overlay {
                Capsule().stroke(border, lineWidth: 0.5)
            }
            .foregroundStyle(foreground)
    }

    private var color: Color {
        if thread.archived || !thread.fileExists { return .red }
        if thread.needsWake { return .orange }
        return .green
    }

    private var foreground: Color {
        isSelected ? .white : color
    }

    private var background: Color {
        isSelected ? .white.opacity(0.18) : color.opacity(0.16)
    }

    private var border: Color {
        isSelected ? .white.opacity(0.22) : color.opacity(0.08)
    }
}

private extension String {
    func matchSnippet(for query: String, radius: Int) -> String? {
        let source = oneLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = source.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }

        let lowerBound = source.index(range.lowerBound, offsetBy: -radius, limitedBy: source.startIndex) ?? source.startIndex
        let upperBound = source.index(range.upperBound, offsetBy: radius, limitedBy: source.endIndex) ?? source.endIndex
        var snippet = String(source[lowerBound..<upperBound])
        if lowerBound > source.startIndex {
            snippet = "..." + snippet
        }
        if upperBound < source.endIndex {
            snippet += "..."
        }
        return snippet
    }
}
