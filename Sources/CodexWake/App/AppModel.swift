import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    private static let backupsSelectionID = "__backups__"

    @Published var isLoading = false
    @Published var status = "Ready"
    @Published var errorMessage: String?
    @Published var searchText = "" {
        didSet { applyFilters() }
    }
    @Published var isDeepSearching = false
    @Published var selectedProjectID = ProjectSummary.allID {
        didSet {
            clearThreadSelection()
            selectedSection = .chats
            applyFilters()
        }
    }
    @Published var selectedSection: AppSection = .chats
    @Published var isSelectingThreads = false
    @Published var selectedThreadIDs = Set<String>()
    @Published var projectSortMode: ProjectSortMode = .recent {
        didSet { projects = ProjectSummary.make(from: threads, sort: projectSortMode) }
    }
    @Published var selectedThreadID: String?
    @Published var selectedBackupID: String?
    @Published private(set) var projects: [ProjectSummary] = [.all]
    @Published private(set) var threads: [CodexThread] = []
    @Published private(set) var filteredThreads: [CodexThread] = []
    @Published private(set) var backups: [BackupFile] = []
    @Published var preview: ThreadPreview?
    @Published var wakeReport: WakeReport?
    @Published var moveReport: MoveReport?
    @Published var batchWakeSuccessMessage: String?
    @Published private(set) var isDemoMode: Bool

    private let store: any ThreadStore
    private var deepSearchTask: Task<Void, Never>?

    var selectedThread: CodexThread? {
        threads.first { $0.id == selectedThreadID }
    }

    var selectedThreads: [CodexThread] {
        threads
            .filter { selectedThreadIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.shortTitle.localizedCaseInsensitiveCompare(rhs.shortTitle) == .orderedAscending
            }
    }

    var wakeableSelectedThreads: [CodexThread] {
        selectedThreads.filter { !$0.archived && $0.fileExists }
    }

    var selectedWakeableCount: Int {
        wakeableSelectedThreads.count
    }

    var selectedWakeSkippedCount: Int {
        selectedThreads.count - wakeableSelectedThreads.count
    }

    var selectedBackup: BackupFile? {
        backups.first { $0.id == selectedBackupID }
    }

    var backupTotalSize: Int64 {
        backups.reduce(0) { $0 + $1.size }
    }

    var backupTotalSizeText: String {
        ByteCountFormatter.string(fromByteCount: backupTotalSize, countStyle: .file)
    }

    var selectedWakeReport: WakeReport? {
        guard wakeReport?.threadID == selectedThreadID else { return nil }
        return wakeReport
    }

    var selectedMoveReport: MoveReport? {
        guard moveReport?.threadID == selectedThreadID else { return nil }
        return moveReport
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
                (threads: try store.loadThreads(), backups: try store.loadBackups())
            }.value
            threads = loaded.threads
            backups = loaded.backups
            projects = ProjectSummary.make(from: loaded.threads, sort: projectSortMode)
            if selectedThreadID == nil {
                selectedThreadID = loaded.threads.first?.id
            }
            if selectedBackupID == nil || !loaded.backups.contains(where: { $0.id == selectedBackupID }) {
                selectedBackupID = loaded.backups.first?.id
            }
            selectedThreadIDs.formIntersection(Set(loaded.threads.map(\.id)))
            if selectedThreadIDs.isEmpty {
                isSelectingThreads = false
            }
            applyFilters()
            preview = nil
            status = isDemoMode ? "Loaded \(loaded.threads.count) demo chats" : "Loaded \(loaded.threads.count) chats"
        } catch {
            errorMessage = readable(error)
            status = "Error"
        }
    }

    func selectThread(_ thread: CodexThread) {
        selectedSection = .chats
        clearThreadSelection()
        selectedThreadID = thread.id
        Task { await loadPreview(threadID: thread.id) }
    }

    func handleThreadClick(_ thread: CodexThread, commandPressed: Bool) {
        selectedSection = .chats
        if commandPressed {
            toggleThreadSelection(thread)
            return
        }

        if isSelectingThreads {
            selectedThreadID = thread.id
            return
        }

        selectThread(thread)
    }

    func startThreadSelection() {
        selectedSection = .chats
        isSelectingThreads = true
        selectedThreadIDs.removeAll()
        batchWakeSuccessMessage = nil
        preview = nil
        status = "Select chats"
    }

    func toggleThreadSelection(_ thread: CodexThread) {
        selectedSection = .chats
        if !isSelectingThreads {
            isSelectingThreads = true
            selectedThreadIDs.removeAll()
            if let selectedThreadID {
                selectedThreadIDs.insert(selectedThreadID)
            }
        }

        if selectedThreadIDs.contains(thread.id) {
            selectedThreadIDs.remove(thread.id)
        } else {
            selectedThreadIDs.insert(thread.id)
        }

        selectedThreadID = thread.id
        batchWakeSuccessMessage = nil
        preview = nil
        status = "\(selectedThreadIDs.count) chats selected"
    }

    func cancelThreadSelection() {
        clearThreadSelection()
        if let selectedThreadID {
            Task { await loadPreview(threadID: selectedThreadID) }
        }
    }

    func revealSelectedThreadsInFinder() {
        guard !isDemoMode else {
            status = "Demo mode has no local files"
            return
        }
        let urls = selectedThreads.map(\.rolloutURL)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func copySelectedThreadPaths() {
        let paths = selectedThreads.map(\.rolloutPath)
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
        status = "Copied \(paths.count) paths"
    }

    func wakeSelectedThreads() async {
        guard !isDemoMode else {
            status = "Demo mode does not change local Codex files"
            return
        }

        let selected = selectedThreads
        guard !selected.isEmpty else { return }

        let skipped = selected.compactMap { thread -> BatchWakeSkipped? in
            if thread.archived {
                return BatchWakeSkipped(threadID: thread.id, title: thread.shortTitle, reason: "Archived")
            }
            if !thread.fileExists {
                return BatchWakeSkipped(threadID: thread.id, title: thread.shortTitle, reason: "Missing file")
            }
            return nil
        }
        let candidates = selected.filter { !$0.archived && $0.fileExists }

        guard !candidates.isEmpty else {
            batchWakeSuccessMessage = "No selected chats can be woken. Skipped \(skipped.count)."
            status = "No selected chats can be woken"
            clearThreadSelection()
            return
        }

        isLoading = true
        status = "Waking \(candidates.count) selected chats..."
        errorMessage = nil
        wakeReport = nil
        moveReport = nil
        batchWakeSuccessMessage = nil
        let firstSelectedID = selected.first?.id
        defer { isLoading = false }

        let store = self.store
        let report = await Task.detached(priority: .userInitiated) {
            var succeeded: [BatchWakeSuccess] = []
            var failed: [BatchWakeFailure] = []

            for thread in candidates {
                do {
                    let report = try store.wake(thread: thread)
                    succeeded.append(
                        BatchWakeSuccess(
                            threadID: thread.id,
                            title: thread.shortTitle,
                            backupCount: report.backups.count
                        )
                    )
                } catch {
                    failed.append(
                        BatchWakeFailure(
                            threadID: thread.id,
                            title: thread.shortTitle,
                            message: AppModel.readableMessage(error)
                        )
                    )
                }
            }

            return BatchWakeReport(
                completedAt: Date(),
                requestedCount: selected.count,
                succeeded: succeeded,
                skipped: skipped,
                failed: failed
            )
        }.value

        batchWakeSuccessMessage = "Woke \(report.succeeded.count) chats. Skipped \(report.skipped.count), failed \(report.failed.count)."
        status = "Batch wake complete: \(report.succeeded.count) ok, \(report.failed.count) failed"
        await refresh()
        selectedThreadID = firstSelectedID
        clearThreadSelection()
        if let selectedThreadID {
            await loadPreview(threadID: selectedThreadID)
        }
    }

    func showBackups() {
        clearThreadSelection()
        selectedProjectID = Self.backupsSelectionID
        selectedSection = .backups
        selectedBackupID = backups.first?.id
        status = backups.isEmpty ? "No backups found" : "Loaded \(backups.count) backups"
    }

    func revealSelectedBackupInFinder() {
        guard !isDemoMode else {
            status = "Demo mode has no local backup file"
            return
        }
        guard let url = selectedBackup.map({ URL(fileURLWithPath: $0.backupPath) }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copySelectedBackupPath() {
        guard let path = selectedBackup?.backupPath else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        status = "Backup path copied"
    }

    func copySelectedBackupOriginalPath() {
        guard let path = selectedBackup?.originalPath else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        status = "Original path copied"
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
            let wokenThreadID = thread.id
            let report = try await Task.detached(priority: .userInitiated) {
                try self.store.wake(thread: thread)
            }.value
            wakeReport = report
            status = "Awake: \(thread.shortTitle)"
            await refresh()
            selectedThreadID = wokenThreadID
            await loadPreview(threadID: wokenThreadID)
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

    private func clearThreadSelection() {
        isSelectingThreads = false
        selectedThreadIDs.removeAll()
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

    private nonisolated static func readableMessage(_ error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
