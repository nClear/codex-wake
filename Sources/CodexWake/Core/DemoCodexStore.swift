import Foundation

final class DemoCodexStore: ThreadStore, @unchecked Sendable {
    private let baseDate = Date(timeIntervalSince1970: 1_779_750_000)
    private let lock = NSLock()
    private var movedProjects: [String: String] = [:]

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

    func loadBackups() throws -> [BackupFile] {
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
                originalExists: true
            )
        }
    }

    func loadPreview(for thread: CodexThread) throws -> ThreadPreview {
        let messages = [
            PreviewMessage(
                role: "user",
                text: thread.firstUserMessage,
                timestamp: WakeDates.isoDemo(thread.createdAt)
            ),
            PreviewMessage(
                role: "assistant",
                text: "I will inspect the local metadata shape first, then make the smallest safe change and verify it with a fresh build.",
                timestamp: WakeDates.isoDemo(thread.createdAt.addingTimeInterval(90))
            ),
            PreviewMessage(
                role: "user",
                text: "Good. Keep the original files untouched, make a backup before changing anything, and show me exactly what changed.",
                timestamp: WakeDates.isoDemo(thread.createdAt.addingTimeInterval(240))
            ),
            PreviewMessage(
                role: "assistant",
                text: "Done. The demo data is intentionally synthetic, search works across titles and preview text, and write actions only update this temporary demo session.",
                timestamp: WakeDates.isoDemo(thread.updatedAt)
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

    private func samplePreview(title: String) -> String {
        "Preview for \(title): synthetic chat content for public screenshots, documentation, and safe UI testing."
    }

    private func movedProjectSnapshot() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return movedProjects
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
