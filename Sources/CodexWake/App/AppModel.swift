import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var isLoading = false
    @Published var status = "Ready"
    @Published var errorMessage: String?
    @Published var searchText = "" {
        didSet { applyFilters() }
    }
    @Published var isDeepSearching = false
    @Published var selectedProjectID = ProjectSummary.allID {
        didSet { applyFilters() }
    }
    @Published var projectSortMode: ProjectSortMode = .recent {
        didSet { projects = ProjectSummary.make(from: threads, sort: projectSortMode) }
    }
    @Published var selectedThreadID: String?
    @Published private(set) var projects: [ProjectSummary] = [.all]
    @Published private(set) var threads: [CodexThread] = []
    @Published private(set) var filteredThreads: [CodexThread] = []
    @Published var preview: ThreadPreview?
    @Published var wakeReport: WakeReport?
    @Published var moveReport: MoveReport?
    @Published private(set) var isDemoMode: Bool

    private let store: any ThreadStore
    private var deepSearchTask: Task<Void, Never>?

    var selectedThread: CodexThread? {
        threads.first { $0.id == selectedThreadID }
    }

    var moveTargetProjects: [ProjectSummary] {
        guard let thread = selectedThread else { return [] }
        return projects.filter { project in
            project.id != ProjectSummary.allID && project.path != thread.cwd
        }
    }

    init(demoMode: Bool = AppModel.detectDemoMode(), store: (any ThreadStore)? = nil) {
        self.isDemoMode = demoMode
        self.store = store ?? (demoMode ? DemoCodexStore() : CodexStore())
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = true
        status = isDemoMode ? "Loading demo chats..." : "Scanning ~/.codex..."
        errorMessage = nil
        defer { isLoading = false }

        do {
            let store = self.store
            let loaded = try await Task.detached(priority: .userInitiated) {
                try store.loadThreads()
            }.value
            threads = loaded
            projects = ProjectSummary.make(from: loaded, sort: projectSortMode)
            if selectedThreadID == nil {
                selectedThreadID = loaded.first?.id
            }
            applyFilters()
            preview = nil
            status = isDemoMode ? "Loaded \(loaded.count) demo chats" : "Loaded \(loaded.count) chats"
        } catch {
            errorMessage = readable(error)
            status = "Error"
        }
    }

    func selectThread(_ thread: CodexThread) {
        selectedThreadID = thread.id
        Task { await loadPreview(threadID: thread.id) }
    }

    func loadPreview(threadID: String) async {
        guard let thread = threads.first(where: { $0.id == threadID }) else {
            preview = nil
            return
        }
        do {
            preview = try await Task.detached(priority: .userInitiated) {
                try self.store.loadPreview(for: thread)
            }.value
        } catch {
            preview = ThreadPreview(threadID: thread.id, messages: [], rawError: readable(error))
        }
    }

    func wakeSelectedThread() async {
        guard let thread = selectedThread else { return }
        guard !isDemoMode else {
            wakeReport = WakeReport(
                threadID: thread.id,
                timestamp: "demo",
                backups: ["Demo mode does not change local Codex files."],
                changedFiles: []
            )
            status = "Demo wake complete"
            return
        }
        isLoading = true
        status = "Waking chat..."
        errorMessage = nil
        wakeReport = nil
        moveReport = nil
        defer { isLoading = false }

        do {
            let report = try await Task.detached(priority: .userInitiated) {
                try self.store.wake(thread: thread)
            }.value
            wakeReport = report
            status = "Awake: \(thread.shortTitle)"
            await refresh()
        } catch {
            errorMessage = readable(error)
            status = "Wake failed"
        }
    }

    func moveSelectedThread(to project: ProjectSummary) async {
        guard let thread = selectedThread else { return }
        isLoading = true
        status = "Moving chat..."
        errorMessage = nil
        wakeReport = nil
        moveReport = nil
        defer { isLoading = false }

        do {
            let report = try await Task.detached(priority: .userInitiated) {
                try self.store.move(thread: thread, to: project)
            }.value
            moveReport = report
            status = "Moved to \(project.name)"
            let movedThreadID = thread.id
            await refresh()
            selectedProjectID = project.id
            selectedThreadID = movedThreadID
            applyFilters()
            await loadPreview(threadID: movedThreadID)
        } catch {
            errorMessage = readable(error)
            status = "Move failed"
        }
    }

    func revealSelectedInFinder() {
        guard !isDemoMode else {
            status = "Demo mode has no local file"
            return
        }
        guard let url = selectedThread?.rolloutURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copySelectedPath() {
        guard !isDemoMode else {
            status = "Demo mode has no local path"
            return
        }
        guard let path = selectedThread?.rolloutPath else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        status = "Path copied"
    }

    func runDeepSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3 else {
            status = "Type at least 3 characters for deep search"
            return
        }

        deepSearchTask?.cancel()
        isDeepSearching = true
        status = "Deep searching..."

        let selectedProject = selectedProjectID
        let source = threads.filter { thread in
            selectedProject == ProjectSummary.allID || thread.cwd == selectedProject
        }
        let metadataMatches = source.filter { $0.matchesMetadata(query) }
        let store = self.store

        deepSearchTask = Task {
            let rawMatches = await Task.detached(priority: .userInitiated) {
                source.filter { thread in
                    if metadataMatches.contains(where: { $0.id == thread.id }) { return false }
                    return (try? store.threadContainsRawText(thread, query: query)) == true
                }
            }.value

            guard !Task.isCancelled else { return }
            filteredThreads = (metadataMatches + rawMatches).sorted { $0.updatedAt > $1.updatedAt }
            isDeepSearching = false
            status = "Deep search found \(filteredThreads.count) chats"
        }
    }

    func cancelDeepSearch() {
        deepSearchTask?.cancel()
        deepSearchTask = nil
        isDeepSearching = false
        status = "Deep search cancelled"
        applyFilters()
    }

    func clearSearch() {
        deepSearchTask?.cancel()
        deepSearchTask = nil
        isDeepSearching = false
        searchText = ""
        status = "Search cleared"
    }

    private func applyFilters() {
        deepSearchTask?.cancel()
        isDeepSearching = false
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedProject = selectedProjectID
        let source = threads.filter { thread in
            selectedProject == ProjectSummary.allID || thread.cwd == selectedProject
        }

        guard !query.isEmpty else {
            filteredThreads = sortThreadsByLatestMessage(source)
            selectFirstFilteredThreadIfNeeded()
            return
        }

        filteredThreads = sortThreadsByLatestMessage(source.filter { thread in
            thread.matchesMetadata(query)
        })
        selectFirstFilteredThreadIfNeeded()
    }

    private func sortThreadsByLatestMessage(_ threads: [CodexThread]) -> [CodexThread] {
        threads.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.shortTitle.localizedCaseInsensitiveCompare(rhs.shortTitle) == .orderedAscending
        }
    }

    private func selectFirstFilteredThreadIfNeeded() {
        guard !filteredThreads.contains(where: { $0.id == selectedThreadID }) else { return }
        selectedThreadID = filteredThreads.first?.id
        preview = nil
    }

    private func readable(_ error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    private nonisolated static func detectDemoMode() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        let env = ProcessInfo.processInfo.environment
        return args.contains("--demo") || env["CODEX_WAKE_DEMO"] == "1"
    }
}
