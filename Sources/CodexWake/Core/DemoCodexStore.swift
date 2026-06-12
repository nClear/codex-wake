import Foundation

final class DemoCodexStore: ThreadStore, @unchecked Sendable {
    private let baseDate = Date(timeIntervalSince1970: 1_779_750_000)
    private let lock = NSLock()
    private var movedProjects: [String: String] = [:]
    private var trashedBackupIDs = Set<String>()
    private var trashedThreadIDs = Set<String>()
    private var permanentlyDeletedThreadIDs = Set<String>()

    func loadThreads() throws -> [CodexThread] {
        let projects = [
            ("/Users/demo/projects/sample-app", "sample-app"),
            ("/Users/demo/projects/design-system", "design-system"),
            ("/Users/demo/projects/docs-workflow", "docs-workflow"),
            ("/Users/demo/projects/release-tools", "release-tools")
        ]

        let rows: [(String, String, String, Int, Bool)] = [
            ("Fix disappearing sidebar threads", "Investigate why older chats vanish from the sidebar and build a safer local recovery workflow.", projects[0].0, 4, true),
            ("Design release screenshot", "Prepare a clean public screenshot with sample data and no private chat content.", projects[0].0, 16, false),
            ("Add demo mode for screenshots", "Create a launch mode that renders realistic sample projects without reading ~/.codex.", projects[0].0, 26, false),
            ("Review onboarding empty state", "Tighten the first-run layout so new users understand what the app can read locally.", projects[1].0, 9 * 24, true),
            ("Compare search result states", "Check hidden, shown, archived, and missing-file rows before publishing the release notes.", projects[1].0, 11 * 24, true),
            ("Plan documentation flow", "Sketch the README structure, install steps, privacy notes, and release download path.", projects[2].0, 42, false),
            ("Clean up transcript preview", "Tune message parsing, timestamps, and long-text wrapping for readable chat previews.", projects[2].0, 13 * 24, true),
            ("Prepare signed release", "Build, sign, notarize, and package the macOS app for the first public release.", projects[3].0, 3 * 24, false),
            ("Render social preview image", "Create a repository preview image that shows the product clearly without leaking real data.", projects[3].0, 18 * 24, true)
        ]

        let overrides = movedProjectSnapshot()
        let trashedThreads = trashedThreadSnapshot()
        let deletedThreads = permanentlyDeletedThreadSnapshot()
        return rows.enumerated().compactMap { index, row in
            let id = "demo-thread-\(String(format: "%03d", index + 1))"
            guard !trashedThreads.contains(id), !deletedThreads.contains(id) else { return nil }
            let cwd = overrides[id] ?? row.2
            let updatedAt = baseDate.addingTimeInterval(-Double(row.3) * 60 * 60)
            let createdAt = updatedAt.addingTimeInterval(-Double(2 + index) * 60 * 60)
            return CodexThread(
                id: id,
                rolloutPath: "/demo/codex-wake/sample-thread-\(index + 1).jsonl",
                createdAt: createdAt,
                updatedAt: updatedAt,
                createdAtMs: createdAt,
                updatedAtMs: updatedAt,
                source: "codex",
                threadSource: row.4 ? "assistant" : "user",
                hasUserEvent: true,
                archived: false,
                title: row.0,
                sessionIndexTitle: row.0,
                firstUserMessage: row.1,
                preview: samplePreview(title: row.0),
                cwd: cwd,
                isInSessionIndex: !row.4,
                sessionIndexUpdatedAt: row.4 ? nil : updatedAt,
                sessionMetaTimestamp: updatedAt,
                sessionPayloadTimestamp: updatedAt,
                fileExists: true
            )
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    func loadBackups() throws -> [BackupFile] {
        return demoBackupSamples()
            .filter { !trashedBackupSnapshot().contains($0.id) }
    }

    func loadBackupTrash() throws -> [BackupFile] {
        demoBackupSamples()
            .filter { trashedBackupSnapshot().contains($0.id) }
    }

    func loadThreadTrash() throws -> [TrashedThread] {
        let trashedThreads = trashedThreadSnapshot()
        let deletedThreads = permanentlyDeletedThreadSnapshot()
        return loadThreadsIncludingTrashed()
            .filter { trashedThreads.contains($0.id) && !deletedThreads.contains($0.id) }
            .map { thread in
                TrashedThread(
                    threadID: thread.id,
                    title: thread.shortTitle,
                    originalPath: thread.rolloutPath,
                    trashPath: "/Users/demo/.codex/.codex-wake-trash/threads/\(thread.id)/\(URL(fileURLWithPath: thread.rolloutPath).lastPathComponent)",
                    manifestPath: "/Users/demo/.codex/.codex-wake-trash/threads/\(thread.id)/manifest.json",
                    cwd: thread.cwd,
                    trashedAt: baseDate,
                    size: 128_000,
                    originalExists: false
                )
            }
    }

    private func loadThreadsIncludingTrashed() -> [CodexThread] {
        let projects = [
            ("/Users/demo/projects/sample-app", "sample-app"),
            ("/Users/demo/projects/design-system", "design-system"),
            ("/Users/demo/projects/docs-workflow", "docs-workflow"),
            ("/Users/demo/projects/release-tools", "release-tools")
        ]

        let rows: [(String, String, String, Int, Bool)] = [
            ("Fix disappearing sidebar threads", "Investigate why older chats vanish from the sidebar and build a safer local recovery workflow.", projects[0].0, 4, true),
            ("Design release screenshot", "Prepare a clean public screenshot with sample data and no private chat content.", projects[0].0, 16, false),
            ("Add demo mode for screenshots", "Create a launch mode that renders realistic sample projects without reading ~/.codex.", projects[0].0, 26, false),
            ("Review onboarding empty state", "Tighten the first-run layout so new users understand what the app can read locally.", projects[1].0, 9 * 24, true),
            ("Compare search result states", "Check hidden, shown, archived, and missing-file rows before publishing the release notes.", projects[1].0, 11 * 24, true),
            ("Plan documentation flow", "Sketch the README structure, install steps, privacy notes, and release download path.", projects[2].0, 42, false),
            ("Clean up transcript preview", "Tune message parsing, timestamps, and long-text wrapping for readable chat previews.", projects[2].0, 13 * 24, true),
            ("Prepare signed release", "Build, sign, notarize, and package the macOS app for the first public release.", projects[3].0, 3 * 24, false),
            ("Render social preview image", "Create a repository preview image that shows the product clearly without leaking real data.", projects[3].0, 18 * 24, true)
        ]

        let overrides = movedProjectSnapshot()
        return rows.enumerated().map { index, row in
            let id = "demo-thread-\(String(format: "%03d", index + 1))"
            let cwd = overrides[id] ?? row.2
            let updatedAt = baseDate.addingTimeInterval(-Double(row.3) * 60 * 60)
            let createdAt = updatedAt.addingTimeInterval(-Double(2 + index) * 60 * 60)
            return CodexThread(
                id: id,
                rolloutPath: "/demo/codex-wake/sample-thread-\(index + 1).jsonl",
                createdAt: createdAt,
                updatedAt: updatedAt,
                createdAtMs: createdAt,
                updatedAtMs: updatedAt,
                source: "codex",
                threadSource: row.4 ? "assistant" : "user",
                hasUserEvent: true,
                archived: false,
                title: row.0,
                sessionIndexTitle: row.0,
                firstUserMessage: row.1,
                preview: samplePreview(title: row.0),
                cwd: cwd,
                isInSessionIndex: !row.4,
                sessionIndexUpdatedAt: row.4 ? nil : updatedAt,
                sessionMetaTimestamp: updatedAt,
                sessionPayloadTimestamp: updatedAt,
                fileExists: true
            )
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func demoBackupSamples() -> [BackupFile] {
        let samples: [(String, BackupKind, Int64, Int)] = [
            ("state_5.sqlite", .stateDatabase, 2_400_000, 1),
            ("state_5.sqlite-wal", .stateDatabase, 180_000, 1),
            ("session_index.jsonl", .sessionIndex, 96_000, 1),
            ("rollout-2026-05-25T17-00-00-demo-thread-001.jsonl", .chatFile, 740_000, 1),
            ("rollout-2026-05-24T11-30-00-demo-thread-004.jsonl", .chatFile, 510_000, 9)
        ]

        return samples.map { originalName, kind, size, hoursAgo in
            let date = baseDate.addingTimeInterval(-Double(hoursAgo) * 60 * 60)
            let stamp = demoBackupStamp(date)
            let directory = kind == .chatFile ? "/Users/demo/.codex/sessions/2026/05/25" : "/Users/demo/.codex"
            let originalPath = "\(directory)/\(originalName)"
            return BackupFile(
                backupPath: "\(originalPath).codex-rescue-backup-\(stamp)",
                originalPath: originalPath,
                originalName: originalName,
                directory: directory,
                stamp: stamp,
                createdAt: date,
                modifiedAt: date,
                size: size,
                kind: kind,
                originalExists: true,
                chatTitle: kind == .chatFile ? "Fix disappearing sidebar threads" : nil,
                reason: kind == .chatFile ? "Created before Trim from here" : "Created by Codex Wake"
            )
        }
    }

    func loadPreview(for thread: CodexThread) throws -> ThreadPreview {
        let messages = [
            PreviewMessage(
                role: "user",
                text: thread.firstUserMessage,
                timestamp: WakeDates.isoDemo(thread.createdAt),
                lineNumber: 8,
                branchLineNumber: 2,
                isTurnStart: true,
                isSteered: false,
                isFirstVisibleUserMessage: true
            ),
            PreviewMessage(
                role: "assistant",
                text: "I will inspect the local metadata shape first, then make the smallest safe change and verify it with a fresh build.",
                timestamp: WakeDates.isoDemo(thread.createdAt.addingTimeInterval(90)),
                lineNumber: 17,
                branchLineNumber: nil,
                isTurnStart: false,
                isSteered: false,
                isFirstVisibleUserMessage: false
            ),
            PreviewMessage(
                role: "user",
                text: "Good. Keep the original files untouched, make a backup before changing anything, and show me exactly what changed.",
                timestamp: WakeDates.isoDemo(thread.createdAt.addingTimeInterval(240)),
                lineNumber: 24,
                branchLineNumber: 22,
                isTurnStart: true,
                isSteered: false,
                isFirstVisibleUserMessage: false
            ),
            PreviewMessage(
                role: "assistant",
                text: "Done. The demo data is intentionally synthetic, search works across titles and preview text, and write actions only update this temporary demo session.",
                timestamp: WakeDates.isoDemo(thread.updatedAt),
                lineNumber: 31,
                branchLineNumber: nil,
                isTurnStart: false,
                isSteered: false,
                isFirstVisibleUserMessage: false
            )
        ]
        return ThreadPreview(threadID: thread.id, messages: messages, rawError: nil)
    }

    func threadContainsRawText(_ thread: CodexThread, query: String) throws -> Bool {
        let q = query.lowercased()
        return [thread.sessionIndexTitle, thread.title, thread.firstUserMessage, thread.preview, thread.cwd]
            .joined(separator: "\n")
            .lowercased()
            .contains(q)
    }

    func wake(thread: CodexThread) throws -> WakeReport {
        WakeReport(
            threadID: thread.id,
            timestamp: "demo",
            backups: ["Demo mode does not read or write local Codex files."],
            changedFiles: []
        )
    }

    func trim(thread: CodexThread, fromLine lineNumber: Int) throws -> TrimReport {
        TrimReport(
            threadID: thread.id,
            timestamp: "demo",
            deletedFromLine: lineNumber,
            removedLineCount: 3,
            backups: ["Demo mode does not read or write local Codex files."],
            changedFiles: []
        )
    }

    func branch(thread: CodexThread, fromLine lineNumber: Int) throws -> BranchReport {
        BranchReport(
            sourceThreadID: thread.id,
            newThreadID: "demo-branch-\(thread.id)",
            title: "Branch: \(thread.shortTitle)",
            createdFromLine: lineNumber,
            keptLineCount: 2,
            rolloutPath: "/demo/codex-wake/branch-\(thread.id).jsonl",
            timestamp: "demo",
            backups: ["Demo mode does not read or write local Codex files."],
            changedFiles: []
        )
    }

    func move(thread: CodexThread, to project: ProjectSummary) throws -> MoveReport {
        lock.lock()
        movedProjects[thread.id] = project.path
        lock.unlock()

        return MoveReport(
            threadID: thread.id,
            fromProject: thread.cwd,
            toProject: project.path,
            timestamp: "demo",
            backups: ["Demo mode does not read or write local Codex files."],
            changedFiles: []
        )
    }

    func moveThreadToTrash(_ thread: CodexThread) throws -> TrashThreadReport {
        lock.lock()
        trashedThreadIDs.insert(thread.id)
        permanentlyDeletedThreadIDs.remove(thread.id)
        lock.unlock()

        return TrashThreadReport(
            threadID: thread.id,
            title: thread.shortTitle,
            rolloutPath: thread.rolloutPath,
            trashedPath: "/Users/demo/.codex/.codex-wake-trash/threads/\(thread.id)/\(URL(fileURLWithPath: thread.rolloutPath).lastPathComponent)",
            timestamp: "demo",
            backups: ["Demo mode does not read or write local Codex files."],
            changedFiles: []
        )
    }

    func restoreTrashedThread(_ thread: TrashedThread) throws {
        lock.lock()
        trashedThreadIDs.remove(thread.threadID)
        permanentlyDeletedThreadIDs.remove(thread.threadID)
        lock.unlock()
    }

    func deleteTrashedThreadPermanently(_ thread: TrashedThread) throws {
        lock.lock()
        permanentlyDeletedThreadIDs.insert(thread.threadID)
        trashedThreadIDs.remove(thread.threadID)
        lock.unlock()
    }

    func restoreBackup(_ backup: BackupFile) throws {
        guard backup.kind == .chatFile else {
            throw WakeError.commandFailed("Only chat file backups can be restored.")
        }
    }

    func moveBackupToTrash(_ backup: BackupFile) throws {
        lock.lock()
        trashedBackupIDs.insert(backup.id)
        lock.unlock()
    }

    func emptyBackupTrash() throws -> Int {
        lock.lock()
        let count = trashedBackupIDs.count
        trashedBackupIDs.removeAll()
        lock.unlock()
        return count
    }

    func emptyThreadTrash() throws -> Int {
        lock.lock()
        let count = trashedThreadIDs.count
        permanentlyDeletedThreadIDs.formUnion(trashedThreadIDs)
        trashedThreadIDs.removeAll()
        lock.unlock()
        return count
    }

    private func samplePreview(title: String) -> String {
        "Preview for \(title): synthetic chat content for public screenshots, documentation, and safe UI testing."
    }

    private func movedProjectSnapshot() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return movedProjects
    }

    private func trashedBackupSnapshot() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return trashedBackupIDs
    }

    private func trashedThreadSnapshot() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return trashedThreadIDs
    }

    private func permanentlyDeletedThreadSnapshot() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return permanentlyDeletedThreadIDs
    }

    private func demoBackupStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

private extension WakeDates {
    static func isoDemo(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
