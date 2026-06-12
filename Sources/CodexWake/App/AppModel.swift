import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    private static let backupsSelectionID = "__backups__"
    private static let backupTrashSelectionID = "__backup_trash__"

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
    @Published var selectedTrashBackupID: String?
    @Published var selectedTrashThreadID: String?
    @Published private(set) var projects: [ProjectSummary] = [.all]
    @Published private(set) var threads: [CodexThread] = []
    @Published private(set) var filteredThreads: [CodexThread] = []
    @Published private(set) var backups: [BackupFile] = []
    @Published private(set) var backupTrash: [BackupFile] = []
    @Published private(set) var threadTrash: [TrashedThread] = []
    @Published var preview: ThreadPreview?
    @Published var isPreviewLoading = false
    @Published var wakeReport: WakeReport?
    @Published var moveReport: MoveReport?
    @Published var trimReport: TrimReport?
    @Published var branchReport: BranchReport?
    @Published var trashThreadReport: TrashThreadReport?
    @Published var batchWakeSuccessMessage: String?
    @Published var batchTrashSuccessMessage: String?
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

    var repairableSelectedThreads: [CodexThread] {
        selectedThreads.filter(\.needsRepair)
    }

    var selectedRepairableCount: Int {
        repairableSelectedThreads.count
    }

    var selectedRepairSkippedCount: Int {
        selectedThreads.count - repairableSelectedThreads.count
    }

    var selectedBackup: BackupFile? {
        backups.first { $0.id == selectedBackupID }
    }

    var selectedTrashBackup: BackupFile? {
        backupTrash.first { $0.id == selectedTrashBackupID }
    }

    var selectedTrashThread: TrashedThread? {
        threadTrash.first { $0.id == selectedTrashThreadID }
    }

    var backupTotalSize: Int64 {
        backups.reduce(0) { $0 + $1.size }
    }

    var backupTotalSizeText: String {
        ByteCountFormatter.string(fromByteCount: backupTotalSize, countStyle: .file)
    }

    var backupTrashTotalSize: Int64 {
        backupTrash.reduce(0) { $0 + $1.size }
    }

    var trashItemCount: Int {
        backupTrash.count + threadTrash.count
    }

    var trashTotalSize: Int64 {
        backupTrash.reduce(0) { $0 + $1.size } + threadTrash.reduce(0) { $0 + $1.size }
    }

    var backupTrashTotalSizeText: String {
        ByteCountFormatter.string(fromByteCount: trashTotalSize, countStyle: .file)
    }

    var selectedWakeReport: WakeReport? {
        guard wakeReport?.threadID == selectedThreadID else { return nil }
        return wakeReport
    }

    var selectedMoveReport: MoveReport? {
        guard moveReport?.threadID == selectedThreadID else { return nil }
        return moveReport
    }

    var selectedTrimReport: TrimReport? {
        guard trimReport?.threadID == selectedThreadID else { return nil }
        return trimReport
    }

    var selectedBranchReport: BranchReport? {
        guard branchReport?.newThreadID == selectedThreadID else { return nil }
        return branchReport
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
                (
                    threads: try store.loadThreads(),
                    backups: try store.loadBackups(),
                    backupTrash: try store.loadBackupTrash(),
                    threadTrash: try store.loadThreadTrash()
                )
            }.value
            threads = loaded.threads
            backups = loaded.backups
            backupTrash = loaded.backupTrash
            threadTrash = loaded.threadTrash
            projects = ProjectSummary.make(from: loaded.threads, sort: projectSortMode)
            if let selectedThreadID, !loaded.threads.contains(where: { $0.id == selectedThreadID }) {
                self.selectedThreadID = nil
                preview = nil
            }
            if selectedBackupID == nil || !loaded.backups.contains(where: { $0.id == selectedBackupID }) {
                selectedBackupID = loaded.backups.first?.id
            }
            if selectedTrashBackupID == nil || !loaded.backupTrash.contains(where: { $0.id == selectedTrashBackupID }) {
                selectedTrashBackupID = loaded.backupTrash.first?.id
            }
            if selectedTrashThreadID == nil || !loaded.threadTrash.contains(where: { $0.id == selectedTrashThreadID }) {
                selectedTrashThreadID = loaded.threadTrash.first?.id
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
        preview = nil
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
        batchTrashSuccessMessage = nil
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
        batchTrashSuccessMessage = nil
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
            if thread.isInSessionIndex {
                return BatchWakeSkipped(threadID: thread.id, title: thread.shortTitle, reason: "Already available")
            }
            return nil
        }
        let candidates = selected.filter(\.needsRepair)

        guard !candidates.isEmpty else {
            batchWakeSuccessMessage = "No selected chats need index repair. Skipped \(skipped.count)."
            status = "No selected chats need repair"
            clearThreadSelection()
            return
        }

        isLoading = true
        status = "Repairing index for \(candidates.count) selected chats..."
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

        batchWakeSuccessMessage = "Repaired \(report.succeeded.count) chats. Skipped \(report.skipped.count), failed \(report.failed.count)."
        status = "Batch repair complete: \(report.succeeded.count) ok, \(report.failed.count) failed"
        await refresh()
        selectedThreadID = firstSelectedID
        clearThreadSelection()
        if let selectedThreadID {
            await loadPreview(threadID: selectedThreadID)
        }
    }

    func moveSelectedThreadsToTrash() async {
        let selected = selectedThreads
        guard !selected.isEmpty else { return }

        isLoading = true
        status = "Moving \(selected.count) selected chats to Trash..."
        errorMessage = nil
        wakeReport = nil
        moveReport = nil
        trimReport = nil
        branchReport = nil
        trashThreadReport = nil
        batchWakeSuccessMessage = nil
        batchTrashSuccessMessage = nil
        defer { isLoading = false }

        let store = self.store
        let result = await Task.detached(priority: .userInitiated) {
            var succeeded: [String] = []
            var failed: [String] = []

            for thread in selected {
                do {
                    _ = try store.moveThreadToTrash(thread)
                    succeeded.append(thread.shortTitle)
                } catch {
                    failed.append("\(thread.shortTitle): \(AppModel.readableMessage(error))")
                }
            }

            return (succeeded: succeeded, failed: failed)
        }.value

        let message = "Moved \(result.succeeded.count) chats to Trash. Failed \(result.failed.count)."
        batchTrashSuccessMessage = result.failed.isEmpty
            ? message
            : message + "\n\n" + result.failed.joined(separator: "\n")
        status = "Trash complete: \(result.succeeded.count) ok, \(result.failed.count) failed"
        clearThreadSelection()
        await refresh()
        selectedProjectID = Self.backupTrashSelectionID
        selectedSection = .backupTrash
        selectedTrashThreadID = threadTrash.first?.id
        selectedTrashBackupID = selectedTrashThreadID == nil ? backupTrash.first?.id : nil
    }

    func showBackups() {
        clearThreadSelection()
        selectedProjectID = Self.backupsSelectionID
        selectedSection = .backups
        selectedBackupID = backups.first?.id
        status = backups.isEmpty ? "No backups found" : "Loaded \(backups.count) backups"
    }

    func showBackupTrash() {
        clearThreadSelection()
        selectedProjectID = Self.backupTrashSelectionID
        selectedSection = .backupTrash
        selectedTrashThreadID = threadTrash.first?.id
        selectedTrashBackupID = selectedTrashThreadID == nil ? backupTrash.first?.id : nil
        status = trashItemCount == 0 ? "App trash is empty" : "Loaded \(trashItemCount) trashed items"
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

    func restoreSelectedBackup() async {
        guard let backup = selectedBackup else { return }
        isLoading = true
        status = "Restoring backup..."
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await Task.detached(priority: .userInitiated) {
                try self.store.restoreBackup(backup)
            }.value
            status = "Chat restored"
            await refresh()
            selectedSection = .backups
            if let selectedThreadID {
                await loadPreview(threadID: selectedThreadID)
            }
        } catch {
            errorMessage = readable(error)
            status = "Restore failed"
        }
    }

    func revealSelectedTrashBackupInFinder() {
        guard !isDemoMode else {
            status = "Demo mode has no local trash file"
            return
        }
        guard let url = selectedTrashBackup.map({ URL(fileURLWithPath: $0.backupPath) }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copySelectedTrashBackupPath() {
        guard let path = selectedTrashBackup?.backupPath else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        status = "Trash path copied"
    }

    func copySelectedTrashBackupOriginalPath() {
        guard let path = selectedTrashBackup?.originalPath else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        status = "Original path copied"
    }

    func selectTrashThread(_ thread: TrashedThread) {
        selectedTrashThreadID = thread.id
        selectedTrashBackupID = nil
    }

    func selectTrashBackup(_ backup: BackupFile) {
        selectedTrashBackupID = backup.id
        selectedTrashThreadID = nil
    }

    func revealSelectedTrashThreadInFinder() {
        guard !isDemoMode else {
            status = "Demo mode has no local trash file"
            return
        }
        guard let path = selectedTrashThread?.trashPath ?? selectedTrashThread?.manifestPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func copySelectedTrashThreadPath() {
        guard let path = selectedTrashThread?.trashPath ?? selectedTrashThread?.manifestPath else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        status = "Trash path copied"
    }

    func copySelectedTrashThreadOriginalPath() {
        guard let path = selectedTrashThread?.originalPath else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        status = "Original path copied"
    }

    func restoreSelectedTrashThread() async {
        guard let thread = selectedTrashThread else { return }
        isLoading = true
        status = "Restoring trashed chat..."
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await Task.detached(priority: .userInitiated) {
                try self.store.restoreTrashedThread(thread)
            }.value
            status = "Chat restored"
            await refresh()
            selectedSection = .chats
            selectedProjectID = thread.cwd
            selectedThreadID = thread.threadID
            applyFilters()
            await loadPreview(threadID: thread.threadID)
        } catch {
            errorMessage = readable(error)
            status = "Restore failed"
        }
    }

    func deleteSelectedTrashThreadPermanently() async {
        guard let thread = selectedTrashThread else { return }
        isLoading = true
        status = "Deleting trashed chat..."
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await Task.detached(priority: .userInitiated) {
                try self.store.deleteTrashedThreadPermanently(thread)
            }.value
            status = "Trashed chat deleted"
            await refresh()
            selectedSection = .backupTrash
        } catch {
            errorMessage = readable(error)
            status = "Delete failed"
        }
    }

    func moveSelectedBackupToTrash() async {
        guard let backup = selectedBackup else { return }
        guard !isDemoMode else {
            do {
                try store.moveBackupToTrash(backup)
                status = "Demo backup moved to trash"
                await refresh()
                selectedSection = .backupTrash
                selectedTrashBackupID = backup.id
            } catch {
                errorMessage = readable(error)
                status = "Move to trash failed"
            }
            return
        }

        isLoading = true
        status = "Moving backup to trash..."
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await Task.detached(priority: .userInitiated) {
                try self.store.moveBackupToTrash(backup)
            }.value
            status = "Backup moved to trash"
            await refresh()
            selectedSection = .backupTrash
            selectedTrashBackupID = backup.id
        } catch {
            errorMessage = readable(error)
            status = "Move to trash failed"
        }
    }

    func emptyBackupTrash() async {
        guard trashItemCount > 0 else { return }
        isLoading = true
        status = "Emptying backup trash..."
        errorMessage = nil
        defer { isLoading = false }

        do {
            let removed = try await Task.detached(priority: .userInitiated) {
                let backups = try self.store.emptyBackupTrash()
                let threads = try self.store.emptyThreadTrash()
                return backups + threads
            }.value
            status = "Deleted \(removed) trashed items"
            await refresh()
        } catch {
            errorMessage = readable(error)
            status = "Empty trash failed"
        }
    }

    func loadPreview(threadID: String) async {
        guard let thread = threads.first(where: { $0.id == threadID }) else {
            preview = nil
            isPreviewLoading = false
            return
        }
        isPreviewLoading = true
        preview = nil
        defer { isPreviewLoading = false }
        do {
            let loadedPreview = try await Task.detached(priority: .userInitiated) {
                try self.store.loadPreview(for: thread)
            }.value
            guard selectedThreadID == threadID else { return }
            preview = loadedPreview
        } catch {
            guard selectedThreadID == threadID else { return }
            preview = ThreadPreview(threadID: thread.id, messages: [], rawError: readable(error))
        }
    }

    func wakeSelectedThread() async {
        guard let thread = selectedThread else { return }
        guard thread.needsRepair || isDemoMode else {
            status = "No index repair needed"
            return
        }
        guard !isDemoMode else {
            wakeReport = WakeReport(
                threadID: thread.id,
                timestamp: "demo",
                backups: ["Demo mode does not change local Codex files."],
                changedFiles: []
            )
            status = "Demo repair complete"
            return
        }
        isLoading = true
        status = "Repairing chat index..."
        errorMessage = nil
        wakeReport = nil
        moveReport = nil
        trimReport = nil
        branchReport = nil
        defer { isLoading = false }

        do {
            let repairedThreadID = thread.id
            let report = try await Task.detached(priority: .userInitiated) {
                try self.store.wake(thread: thread)
            }.value
            wakeReport = report
            status = "Index repaired: \(thread.shortTitle)"
            await refresh()
            selectedThreadID = repairedThreadID
            await loadPreview(threadID: repairedThreadID)
        } catch {
            errorMessage = readable(error)
            status = "Repair failed"
        }
    }

    func trimSelectedThread(from message: PreviewMessage) async {
        guard let thread = selectedThread, let lineNumber = message.lineNumber else { return }
        guard message.canTrimFromHere else {
            status = "Cannot trim the first visible user message"
            return
        }
        isLoading = true
        status = "Trimming chat..."
        errorMessage = nil
        wakeReport = nil
        moveReport = nil
        trimReport = nil
        branchReport = nil
        defer { isLoading = false }

        do {
            let trimmedThreadID = thread.id
            let report = try await Task.detached(priority: .userInitiated) {
                try self.store.trim(thread: thread, fromLine: lineNumber)
            }.value
            trimReport = report
            status = "Trimmed: \(thread.shortTitle)"
            await refresh()
            selectedThreadID = trimmedThreadID
            await loadPreview(threadID: trimmedThreadID)
        } catch {
            errorMessage = readable(error)
            status = "Trim failed"
        }
    }

    func branchSelectedThread(from message: PreviewMessage) async {
        guard let thread = selectedThread, let lineNumber = message.branchLineNumber else { return }
        isLoading = true
        status = "Creating chat branch..."
        errorMessage = nil
        wakeReport = nil
        moveReport = nil
        trimReport = nil
        branchReport = nil
        defer { isLoading = false }

        do {
            let report = try await Task.detached(priority: .userInitiated) {
                try self.store.branch(thread: thread, fromLine: lineNumber)
            }.value
            branchReport = report
            status = "Branched: \(report.title)"
            await refresh()
            selectedProjectID = thread.cwd
            selectedThreadID = report.newThreadID
            applyFilters()
            await loadPreview(threadID: report.newThreadID)
        } catch {
            errorMessage = readable(error)
            status = "Branch failed"
        }
    }

    func moveSelectedThread(to project: ProjectSummary) async {
        guard let thread = selectedThread else { return }
        isLoading = true
        status = "Moving chat..."
        errorMessage = nil
        wakeReport = nil
        moveReport = nil
        trimReport = nil
        branchReport = nil
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

    func moveSelectedThreadToTrash() async {
        guard let thread = selectedThread else { return }
        isLoading = true
        status = "Moving chat to Trash..."
        errorMessage = nil
        wakeReport = nil
        moveReport = nil
        trimReport = nil
        branchReport = nil
        trashThreadReport = nil
        defer { isLoading = false }

        do {
            let report = try await Task.detached(priority: .userInitiated) {
                try self.store.moveThreadToTrash(thread)
            }.value
            trashThreadReport = report
            status = "Moved to Trash: \(thread.shortTitle)"
            await refresh()
            selectedProjectID = Self.backupTrashSelectionID
            selectedSection = .backupTrash
            selectedTrashThreadID = report.threadID
            selectedTrashBackupID = nil
        } catch {
            errorMessage = readable(error)
            status = "Move to Trash failed"
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

    func revealThreadInFinder(_ thread: CodexThread) {
        guard !isDemoMode else {
            status = "Demo mode has no local file"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([thread.rolloutURL])
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

    func copyThreadPath(_ thread: CodexThread) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(thread.rolloutPath, forType: .string)
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
        selectedThreadID = nil
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
