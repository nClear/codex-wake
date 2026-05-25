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
    @Published var selectedThreadID: String?
    @Published private(set) var projects: [ProjectSummary] = [.all]
    @Published private(set) var threads: [CodexThread] = []
    @Published private(set) var filteredThreads: [CodexThread] = []
    @Published var preview: ThreadPreview?
    @Published var wakeReport: WakeReport?

    private let store = CodexStore()
    private var deepSearchTask: Task<Void, Never>?

    var selectedThread: CodexThread? {
        threads.first { $0.id == selectedThreadID }
    }

    init() {
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = true
        status = "Scanning ~/.codex..."
        errorMessage = nil
        defer { isLoading = false }

        do {
            let store = self.store
            let loaded = try await Task.detached(priority: .userInitiated) {
                try store.loadThreads()
            }.value
            threads = loaded
            projects = ProjectSummary.make(from: loaded)
            if selectedThreadID == nil {
                selectedThreadID = loaded.first?.id
            }
            applyFilters()
            preview = nil
            status = "Loaded \(loaded.count) chats"
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
        isLoading = true
        status = "Waking chat..."
        errorMessage = nil
        wakeReport = nil
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

    func revealSelectedInFinder() {
        guard let url = selectedThread?.rolloutURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copySelectedPath() {
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
            filteredThreads = source
            return
        }

        filteredThreads = source.filter { thread in
            thread.matchesMetadata(query)
        }
    }

    private func readable(_ error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
