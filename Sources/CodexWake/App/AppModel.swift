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
    @Published var selectedThreadIDs: Set<String> = []
    @Published var selectedBackupIDs: Set<String> = []
    @Published private(set) var projects: [ProjectSummary] = [.all]
    @Published private(set) var threads: [CodexThread] = []
    @Published private(set) var filteredThreads: [CodexThread] = []
    @Published private(set) var backups: [BackupFile] = []
    @Published private(set) var isLoadingBackups = false
    @Published var preview: ThreadPreview?
    @Published var operationReport: OperationReport?
    @Published private(set) var isDemoMode: Bool

    private let store: any ThreadStore
    private var deepSearchTask: Task<Void, Never>?

    var selectedThread: CodexThread? {
        threads.first { $0.id == selectedThreadID }
    }

    var selectedThreads: [CodexThread] {
        orderedThreads(for: selectedThreadIDs)
    }

    var selectedThreadCount: Int {
        selectedThreadIDs.count
    }

    var canOperateOnSelectedThreads: Bool {
        selectedThreads.contains { !$0.archived && $0.fileExists }
    }

    var moveTargetProjects: [ProjectSummary] {
        let movableThreads = selectedThreads.filter { !$0.archived && $0.fileExists }
        guard !movableThreads.isEmpty else { return [] }
        return projects.filter { project in
            project.id != ProjectSummary.allID && !movableThreads.allSatisfy { $0.cwd == project.path }
        }
    }

    var selectedOperationReport: OperationReport? {
        guard let selectedThreadID,
              let report = operationReport,
              report.threadIDs.contains(selectedThreadID)
        else { return nil }
        return report
    }

    var totalBackupSize: Int64 {
        backups.reduce(0) { $0 + $1.size }
    }

    var selectedBackupSize: Int64 {
        selectedBackups.reduce(0) { $0 + $1.size }
    }

    var backupSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: totalBackupSize, countStyle: .file)
    }

    var selectedBackupSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: selectedBackupSize, countStyle: .file)
    }

    var selectedBackups: [BackupFile] {
        let ids = selectedBackupIDs
        return backups.filter { ids.contains($0.id) }
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
            projects = ProjectSummary.make(from: loaded)
            if selectedThreadIDs.isEmpty, let first = loaded.first {
                selectedThreadIDs = [first.id]
                selectedThreadID = first.id
            }
            applyFilters()
            status = isDemoMode ? "Loaded \(loaded.count) demo chats" : "Loaded \(loaded.count) chats"
            if let selectedThreadID {
                await loadPreview(threadID: selectedThreadID)
            } else {
                preview = nil
            }
        } catch {
            errorMessage = Self.readable(error)
            status = "Error"
        }
    }

    func updateThreadSelection(_ ids: Set<String>, preferredID: String? = nil) {
        setSelection(ids, preferredID: preferredID, shouldLoadPreview: true)
    }

    func selectThread(_ thread: CodexThread) {
        setSelection([thread.id], preferredID: thread.id, shouldLoadPreview: true)
    }

    func focusContextSelection(on thread: CodexThread) {
        if selectedThreadIDs.contains(thread.id) {
            setSelection(selectedThreadIDs, preferredID: thread.id, shouldLoadPreview: true)
        } else {
            selectThread(thread)
        }
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
            preview = ThreadPreview(threadID: thread.id, messages: [], rawError: Self.readable(error))
        }
    }

    func wakeSelectedThread() async {
        await wakeSelectedThreads()
    }

    func wakeSelectedThreads() async {
        await wakeThreads(ids: selectedThreadIDs)
    }

    func wakeThreads(ids: Set<String>) async {
        let targets = orderedThreads(for: ids).filter { !$0.archived && $0.fileExists }
        guard !targets.isEmpty else {
            status = "No selectable chats can be woken"
            return
        }

        isLoading = true
        status = targets.count == 1 ? "Waking chat..." : "Waking \(targets.count) chats..."
        errorMessage = nil
        operationReport = nil
        defer { isLoading = false }

        let store = self.store
        let result = await Task.detached(priority: .userInitiated) {
            var backups: [String] = []
            var changedFiles: [String] = []
            var failures: [String] = []
            var successIDs: Set<String> = []

            for thread in targets {
                do {
                    let report = try store.wake(thread: thread)
                    backups.append(contentsOf: report.backups)
                    changedFiles.append(contentsOf: report.changedFiles)
                    successIDs.insert(thread.id)
                } catch {
                    failures.append("\(thread.shortTitle): \(Self.readable(error))")
                }
            }

            return BatchOperationResult(
                targetIDs: Set(targets.map(\.id)),
                successIDs: successIDs,
                backups: backups,
                changedFiles: changedFiles,
                failures: failures
            )
        }.value

        operationReport = OperationReport(
            title: "Wake complete",
            threadIDs: result.targetIDs,
            timestamp: WakeDates.display(Date()),
            summary: "\(result.successIDs.count) of \(targets.count) chats updated",
            backups: result.backups,
            changedFiles: Array(Set(result.changedFiles)).sorted(),
            failures: result.failures
        )
        status = result.failures.isEmpty ? "Wake complete" : "Wake completed with \(result.failures.count) failures"

        let idsToKeep = ids
        await refresh()
        setSelection(idsToKeep, shouldLoadPreview: true)
    }

    func moveSelectedThread(to project: ProjectSummary) async {
        await moveSelectedThreads(to: project)
    }

    func moveSelectedThreads(to project: ProjectSummary) async {
        let targets = orderedThreads(for: selectedThreadIDs).filter {
            !$0.archived && $0.fileExists && $0.cwd != project.path
        }
        guard !targets.isEmpty else {
            status = "No selected chats need to move"
            return
        }

        isLoading = true
        status = targets.count == 1 ? "Moving chat..." : "Moving \(targets.count) chats..."
        errorMessage = nil
        operationReport = nil
        defer { isLoading = false }

        let store = self.store
        let result = await Task.detached(priority: .userInitiated) {
            var backups: [String] = []
            var changedFiles: [String] = []
            var failures: [String] = []
            var successIDs: Set<String> = []

            for thread in targets {
                do {
                    let report = try store.move(thread: thread, to: project)
                    backups.append(contentsOf: report.backups)
                    changedFiles.append(contentsOf: report.changedFiles)
                    successIDs.insert(thread.id)
                } catch {
                    failures.append("\(thread.shortTitle): \(Self.readable(error))")
                }
            }

            return BatchOperationResult(
                targetIDs: Set(targets.map(\.id)),
                successIDs: successIDs,
                backups: backups,
                changedFiles: changedFiles,
                failures: failures
            )
        }.value

        operationReport = OperationReport(
            title: "Move complete",
            threadIDs: result.targetIDs,
            timestamp: WakeDates.display(Date()),
            summary: "\(result.successIDs.count) of \(targets.count) chats moved to \(project.name)",
            backups: result.backups,
            changedFiles: Array(Set(result.changedFiles)).sorted(),
            failures: result.failures
        )
        status = result.failures.isEmpty ? "Moved to \(project.name)" : "Move completed with \(result.failures.count) failures"

        await refresh()
        selectedProjectID = project.id
        setSelection(result.successIDs.isEmpty ? Set(targets.map(\.id)) : result.successIDs, shouldLoadPreview: true)
    }

    func revealSelectedInFinder() {
        revealThreadsInFinder(ids: selectedThreadIDs)
    }

    func revealThreadsInFinder(ids: Set<String>) {
        guard !isDemoMode else {
            status = "Demo mode has no local files"
            return
        }
        let urls = orderedThreads(for: ids)
            .filter(\.fileExists)
            .map(\.rolloutURL)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func copySelectedPath() {
        copyThreadPaths(ids: selectedThreadIDs)
    }

    func copyThreadPaths(ids: Set<String>) {
        guard !isDemoMode else {
            status = "Demo mode has no local paths"
            return
        }
        let paths = orderedThreads(for: ids).map(\.rolloutPath)
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
        status = paths.count == 1 ? "Path copied" : "\(paths.count) paths copied"
    }

    func refreshBackups() async {
        isLoadingBackups = true
        errorMessage = nil
        defer { isLoadingBackups = false }

        do {
            let store = self.store
            let loaded = try await Task.detached(priority: .userInitiated) {
                try store.loadBackups()
            }.value
            backups = loaded
            selectedBackupIDs = selectedBackupIDs.intersection(Set(loaded.map(\.id)))
            status = loaded.isEmpty ? "No backups found" : "Found \(loaded.count) backups"
        } catch {
            errorMessage = Self.readable(error)
            status = "Backup scan failed"
        }
    }

    func deleteSelectedBackups() async {
        await deleteBackups(paths: selectedBackupIDs)
    }

    func deleteAllBackups() async {
        await deleteBackups(paths: Set(backups.map(\.id)))
    }

    func deleteBackups(paths: Set<String>) async {
        guard !paths.isEmpty else { return }
        isLoadingBackups = true
        errorMessage = nil
        defer { isLoadingBackups = false }

        do {
            let store = self.store
            let deletedCount = try await Task.detached(priority: .userInitiated) {
                try store.deleteBackups(paths: paths)
            }.value
            backups.removeAll { paths.contains($0.id) }
            selectedBackupIDs.subtract(paths)
            status = "Deleted \(deletedCount) backups"
        } catch {
            errorMessage = Self.readable(error)
            status = "Backup delete failed"
        }
    }

    func revealSelectedBackupsInFinder() {
        guard !isDemoMode else {
            status = "Demo mode has no local backup files"
            return
        }
        let urls = selectedBackups.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func copySelectedBackupPaths() {
        let paths = selectedBackups.map(\.path)
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
        status = paths.count == 1 ? "Backup path copied" : "\(paths.count) backup paths copied"
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
            selectFirstFilteredThreadIfNeeded()
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
            selectFirstFilteredThreadIfNeeded()
            return
        }

        filteredThreads = source.filter { thread in
            thread.matchesMetadata(query)
        }
        selectFirstFilteredThreadIfNeeded()
    }

    private func selectFirstFilteredThreadIfNeeded() {
        guard !filteredThreads.isEmpty else {
            selectedThreadIDs = []
            selectedThreadID = nil
            preview = nil
            return
        }

        let visibleIDs = Set(filteredThreads.map(\.id))
        var retainedSelection = selectedThreadIDs.intersection(visibleIDs)
        if retainedSelection.isEmpty, let first = filteredThreads.first {
            retainedSelection = [first.id]
        }
        setSelection(retainedSelection, shouldLoadPreview: true)
    }

    private func setSelection(_ ids: Set<String>, preferredID: String? = nil, shouldLoadPreview: Bool) {
        let visibleIDs = Set(filteredThreads.map(\.id))
        let validIDs = ids.intersection(visibleIDs)
        selectedThreadIDs = validIDs

        let nextID: String?
        if let preferredID, validIDs.contains(preferredID) {
            nextID = preferredID
        } else if let selectedThreadID, validIDs.contains(selectedThreadID) {
            nextID = selectedThreadID
        } else {
            nextID = filteredThreads.first(where: { validIDs.contains($0.id) })?.id
        }

        guard nextID != selectedThreadID else { return }
        selectedThreadID = nextID
        preview = nil
        if shouldLoadPreview, let nextID {
            Task { await loadPreview(threadID: nextID) }
        }
    }

    private func orderedThreads(for ids: Set<String>) -> [CodexThread] {
        guard !ids.isEmpty else { return [] }

        var seen: Set<String> = []
        var ordered: [CodexThread] = []
        for thread in filteredThreads + threads {
            guard ids.contains(thread.id), !seen.contains(thread.id) else { continue }
            ordered.append(thread)
            seen.insert(thread.id)
        }
        return ordered
    }

    private nonisolated static func readable(_ error: Error) -> String {
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

private struct BatchOperationResult {
    let targetIDs: Set<String>
    let successIDs: Set<String>
    let backups: [String]
    let changedFiles: [String]
    let failures: [String]
}
