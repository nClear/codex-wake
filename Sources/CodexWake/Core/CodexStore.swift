import Foundation
import SQLite3

final class CodexStore: ThreadStore, @unchecked Sendable {
    private let fileManager = FileManager.default
    private let codexHome: URL
    private let stateDB: URL
    private let sessionIndex: URL
    private let backupTrash: URL
    private let threadTrash: URL

    init(codexHome: URL? = nil) {
        let home = codexHome ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        self.codexHome = home
        self.stateDB = home.appendingPathComponent("state_5.sqlite")
        self.sessionIndex = home.appendingPathComponent("session_index.jsonl")
        self.backupTrash = home.appendingPathComponent(".codex-wake-trash", isDirectory: true)
        self.threadTrash = backupTrash.appendingPathComponent("threads", isDirectory: true)
    }

    func loadThreads() throws -> [CodexThread] {
        guard fileManager.fileExists(atPath: codexHome.path) else { throw WakeError.missingCodexHome(codexHome) }
        guard fileManager.fileExists(atPath: stateDB.path) else { throw WakeError.missingStateDatabase(stateDB) }

        let index = try loadSessionIndex()
        let rows = try loadThreadRows()
        return rows.map { row in
            let indexEntry = index[row.id]
            return CodexThread(
                id: row.id,
                rolloutPath: row.rollout_path,
                createdAt: WakeDates.dateFromSeconds(row.created_at) ?? Date.distantPast,
                updatedAt: WakeDates.dateFromSeconds(row.updated_at) ?? Date.distantPast,
                createdAtMs: WakeDates.dateFromMilliseconds(row.created_at_ms),
                updatedAtMs: WakeDates.dateFromMilliseconds(row.updated_at_ms),
                source: row.source,
                threadSource: row.thread_source ?? "",
                hasUserEvent: (row.has_user_event ?? 0) != 0,
                archived: (row.archived ?? 0) != 0,
                title: row.title,
                sessionIndexTitle: indexEntry?.thread_name ?? "",
                firstUserMessage: row.first_user_message ?? "",
                preview: row.preview ?? "",
                cwd: row.cwd,
                isInSessionIndex: indexEntry != nil,
                sessionIndexUpdatedAt: WakeDates.parseISO(indexEntry?.updated_at),
                sessionMetaTimestamp: nil,
                sessionPayloadTimestamp: nil,
                fileExists: fileManager.fileExists(atPath: row.rollout_path)
            )
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    func loadBackups() throws -> [BackupFile] {
        guard fileManager.fileExists(atPath: codexHome.path) else { throw WakeError.missingCodexHome(codexHome) }
        return try scanBackups(in: codexHome, includeTrash: false).filter(isMainBackup)
    }

    func loadBackupTrash() throws -> [BackupFile] {
        guard fileManager.fileExists(atPath: backupTrash.path) else { return [] }
        return try scanBackups(in: backupTrash, includeTrash: true)
    }

    func loadThreadTrash() throws -> [TrashedThread] {
        guard fileManager.fileExists(atPath: threadTrash.path) else { return [] }
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: threadTrash,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var threads: [TrashedThread] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "manifest.json" else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile != false else { continue }
            let data = try Data(contentsOf: url)
            let manifest = try JSONDecoder().decode(TrashedThreadManifest.self, from: data)
            let trashURL = manifest.trashPath.map { URL(fileURLWithPath: $0) }
            let size = trashURL.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.map(Int64.init) ?? 0
            threads.append(
                TrashedThread(
                    threadID: manifest.threadID,
                    title: manifest.title,
                    originalPath: manifest.originalPath,
                    trashPath: manifest.trashPath,
                    manifestPath: url.path,
                    cwd: manifest.cwd,
                    trashedAt: WakeDates.parseISO(manifest.trashedAt),
                    size: size,
                    originalExists: fileManager.fileExists(atPath: manifest.originalPath)
                )
            )
        }

        return threads.sorted { lhs, rhs in
            let lhsDate = lhs.trashedAt ?? .distantPast
            let rhsDate = rhs.trashedAt ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func scanBackups(in root: URL, includeTrash: Bool) throws -> [BackupFile] {
        let marker = ".codex-rescue-backup-"
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let options: FileManager.DirectoryEnumerationOptions = includeTrash
            ? [.skipsPackageDescendants]
            : [.skipsPackageDescendants, .skipsHiddenFiles]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: options
        ) else {
            return []
        }

        let sessionIndexEntries = (try? loadSessionIndex()) ?? [:]
        var backups: [BackupFile] = []
        for case let url as URL in enumerator {
            if !includeTrash && url.path.hasPrefix(backupTrash.path + "/") { continue }
            let fileName = url.lastPathComponent
            guard let markerRange = fileName.range(of: marker) else { continue }

            let originalName = String(fileName[..<markerRange.lowerBound])
            let stamp = String(fileName[markerRange.upperBound...])
            guard !originalName.isEmpty, !stamp.isEmpty else { continue }

            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == false { continue }

            let directoryURL = url.deletingLastPathComponent()
            let originalDirectoryURL: URL
            if includeTrash {
                let relativeDirectory = String(directoryURL.path.dropFirst(backupTrash.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                originalDirectoryURL = relativeDirectory.isEmpty
                    ? codexHome
                    : codexHome.appendingPathComponent(relativeDirectory, isDirectory: true)
            } else {
                originalDirectoryURL = directoryURL
            }
            let originalURL = originalDirectoryURL.appendingPathComponent(originalName)
            let kind = backupKind(for: originalName)
            let chatTitle = kind == .chatFile ? backupChatTitle(from: url, sessionIndex: sessionIndexEntries) : nil
            backups.append(
                BackupFile(
                    backupPath: url.path,
                    originalPath: originalURL.path,
                    originalName: originalName,
                    directory: directoryURL.path,
                    stamp: stamp,
                    createdAt: WakeDates.dateFromBackupStamp(stamp),
                    modifiedAt: values?.contentModificationDate,
                    size: Int64(values?.fileSize ?? 0),
                    kind: kind,
                    originalExists: fileManager.fileExists(atPath: originalURL.path),
                    chatTitle: chatTitle,
                    reason: backupReason(for: stamp, kind: kind)
                )
            )
        }

        return backups.sorted { lhs, rhs in
            let lhsDate = lhs.createdAt ?? lhs.modifiedAt ?? .distantPast
            let rhsDate = rhs.createdAt ?? rhs.modifiedAt ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.backupPath.localizedCaseInsensitiveCompare(rhs.backupPath) == .orderedAscending
        }
    }

    func moveBackupToTrash(_ backup: BackupFile) throws {
        let source = URL(fileURLWithPath: backup.backupPath).standardizedFileURL
        guard source.path.hasPrefix(codexHome.standardizedFileURL.path + "/"),
              source.lastPathComponent.contains(".codex-rescue-backup-")
        else {
            throw WakeError.commandFailed("Refusing to move non-Codex-Wake backup file")
        }

        let sourceDirectory = source.deletingLastPathComponent()
        let relativeDirectory = String(sourceDirectory.path.dropFirst(codexHome.standardizedFileURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let destinationDirectory = relativeDirectory.isEmpty
            ? backupTrash
            : backupTrash.appendingPathComponent(relativeDirectory, isDirectory: true)
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destination = uniqueTrashURL(for: source.lastPathComponent, in: destinationDirectory)
        try fileManager.moveItem(at: source, to: destination)
    }

    func restoreBackup(_ backupFile: BackupFile) throws {
        guard backupFile.kind == .chatFile else {
            throw WakeError.commandFailed("Only chat file backups can be restored.")
        }

        let backupURL = URL(fileURLWithPath: backupFile.backupPath).standardizedFileURL
        let originalURL = URL(fileURLWithPath: backupFile.originalPath).standardizedFileURL
        guard backupURL.path.hasPrefix(codexHome.standardizedFileURL.path + "/"),
              backupURL.lastPathComponent.contains(".codex-rescue-backup-")
        else {
            throw WakeError.commandFailed("Refusing to restore non-Codex-Wake backup file.")
        }
        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw WakeError.commandFailed("Backup file no longer exists.")
        }

        try fileManager.createDirectory(at: originalURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let temporaryURL = originalURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(originalURL.lastPathComponent).codex-wake-restore-\(backupStamp())")
        if fileManager.fileExists(atPath: temporaryURL.path) {
            try fileManager.removeItem(at: temporaryURL)
        }
        try fileManager.copyItem(at: backupURL, to: temporaryURL)
        defer { try? fileManager.removeItem(at: temporaryURL) }

        if fileManager.fileExists(atPath: originalURL.path) {
            _ = try fileManager.replaceItemAt(originalURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: originalURL)
        }
    }

    func emptyBackupTrash() throws -> Int {
        guard fileManager.fileExists(atPath: backupTrash.path) else { return 0 }
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: backupTrash,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else {
            return 0
        }

        var removed = 0
        for case let url as URL in enumerator {
            let standardized = url.standardizedFileURL
            guard standardized.path.hasPrefix(backupTrash.standardizedFileURL.path + "/"),
                  standardized.lastPathComponent.contains(".codex-rescue-backup-")
            else { continue }

            let values = try? standardized.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile != false else { continue }
            try fileManager.removeItem(at: standardized)
            removed += 1
        }
        return removed
    }

    func loadPreview(for thread: CodexThread) throws -> ThreadPreview {
        guard fileManager.fileExists(atPath: thread.rolloutPath) else {
            throw WakeError.missingThreadFile(thread.rolloutPath)
        }

        let content = try String(contentsOf: URL(fileURLWithPath: thread.rolloutPath), encoding: .utf8)
        var messages: [PreviewMessage] = []
        var currentTurnStartLine: Int?
        var hasVisibleUserMessageInTurn = false
        var visibleUserMessageCount = 0
        var pendingTurnComplete: PreviewMessage?
        for (index, line) in content.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            guard let data = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let lineNumber = index + 1

            if let eventType = (obj["payload"] as? [String: Any])?["type"] as? String {
                if obj["type"] as? String == "event_msg", eventType == "task_started" {
                    currentTurnStartLine = lineNumber
                    hasVisibleUserMessageInTurn = false
                    pendingTurnComplete = nil
                } else if obj["type"] as? String == "event_msg", eventType == "task_complete" {
                    if let pendingTurnComplete {
                        messages.append(pendingTurnComplete)
                    }
                    currentTurnStartLine = nil
                    hasVisibleUserMessageInTurn = false
                    pendingTurnComplete = nil
                    continue
                }
            }

            let isTurnStartMessage = currentTurnStartLine != nil && !hasVisibleUserMessageInTurn
            let branchLineNumber = isTurnStartMessage ? currentTurnStartLine : nil
            if let message = extractMessage(
                from: obj,
                lineNumber: lineNumber,
                branchLineNumber: branchLineNumber,
                isTurnStart: isTurnStartMessage,
                isSteered: !isTurnStartMessage && isUserObject(obj),
                isFirstVisibleUserMessage: isUserObject(obj) && visibleUserMessageCount == 0
            ) {
                if message.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "assistant" {
                    pendingTurnComplete = message
                    continue
                }
                messages.append(message)
                if message.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "user" {
                    visibleUserMessageCount += 1
                    hasVisibleUserMessageInTurn = true
                }
            }
        }

        return ThreadPreview(threadID: thread.id, messages: messages, rawError: nil)
    }

    func threadContainsRawText(_ thread: CodexThread, query: String) throws -> Bool {
        guard fileManager.fileExists(atPath: thread.rolloutPath) else { return false }
        guard query.count >= 3 else { return false }
        let handle = try FileHandle(forReadingFrom: thread.rolloutURL)
        defer { try? handle.close() }

        let lowerQuery = query.lowercased()
        while true {
            if Task.isCancelled { return false }
            let data = handle.readData(ofLength: 512 * 1024)
            if data.isEmpty { return false }
            guard let chunk = String(data: data, encoding: .utf8)?.lowercased() else { continue }
            if chunk.contains(lowerQuery) { return true }
        }
    }

    func wake(thread: CodexThread) throws -> WakeReport {
        guard fileManager.fileExists(atPath: thread.rolloutPath) else {
            throw WakeError.missingThreadFile(thread.rolloutPath)
        }

        let stamp = backupStamp()
        let backupSuffix = "\(stamp)-wake"
        var backups: [String] = []
        var changed: [String] = []

        backups += try backupStateFiles(stamp: backupSuffix)
        backups.append(try backup(sessionIndex, suffix: backupSuffix).path)
        backups.append(try backup(thread.rolloutURL, suffix: backupSuffix).path)

        let nowSeconds = Int64(Date().timeIntervalSince1970)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        try updateSQLite(threadID: thread.id, updatedAt: nowSeconds, updatedAtMs: nowMs)
        changed.append(stateDB.path)

        try updateSessionIndex(threadID: thread.id, updatedAt: WakeDates.isoNowForIndex())
        changed.append(sessionIndex.path)

        try updateSessionMeta(path: thread.rolloutURL, timestamp: WakeDates.isoNowForJSONL())
        changed.append(thread.rolloutPath)

        return WakeReport(threadID: thread.id, timestamp: stamp, backups: backups, changedFiles: changed)
    }

    func trim(thread: CodexThread, fromLine lineNumber: Int) throws -> TrimReport {
        guard fileManager.fileExists(atPath: thread.rolloutPath) else {
            throw WakeError.missingThreadFile(thread.rolloutPath)
        }
        guard lineNumber > 1 else {
            throw WakeError.commandFailed("Cannot trim before the first JSONL line.")
        }

        let stamp = backupStamp()
        let rolloutURL = thread.rolloutURL
        let backupPath = try backup(rolloutURL, suffix: "\(stamp)-trim").path

        let content = try String(contentsOf: rolloutURL, encoding: .utf8)
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" {
            lines.removeLast()
        }
        guard lineNumber <= lines.count else {
            throw WakeError.commandFailed("Trim line is outside the chat file.")
        }

        let keptLines = Array(lines.prefix(lineNumber - 1))
        let removedLineCount = lines.count - keptLines.count
        let trimmedContent = keptLines.joined(separator: "\n") + "\n"
        try trimmedContent.write(to: rolloutURL, atomically: true, encoding: .utf8)

        return TrimReport(
            threadID: thread.id,
            timestamp: stamp,
            deletedFromLine: lineNumber,
            removedLineCount: removedLineCount,
            backups: [backupPath],
            changedFiles: [thread.rolloutPath]
        )
    }

    func branch(thread: CodexThread, fromLine lineNumber: Int) throws -> BranchReport {
        guard fileManager.fileExists(atPath: thread.rolloutPath) else {
            throw WakeError.missingThreadFile(thread.rolloutPath)
        }
        guard lineNumber > 1 else {
            throw WakeError.commandFailed("Cannot branch before the first JSONL line.")
        }

        let content = try String(contentsOf: thread.rolloutURL, encoding: .utf8)
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" {
            lines.removeLast()
        }
        guard lineNumber <= lines.count else {
            throw WakeError.commandFailed("Branch line is outside the chat file.")
        }

        let keptLines = Array(lines.prefix(lineNumber - 1))
        guard !keptLines.isEmpty else {
            throw WakeError.commandFailed("Branch would create an empty chat.")
        }

        let stamp = backupStamp()
        let now = Date()
        let nowSeconds = Int64(now.timeIntervalSince1970)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let nowJSONL = WakeDates.isoNowForJSONL()
        let nowIndex = WakeDates.isoNowForIndex()
        let newThreadID = try uniqueThreadID()
        let newTitle = branchTitle(for: thread)
        let newRolloutURL = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(branchDatePath(now), isDirectory: true)
            .appendingPathComponent("rollout-\(branchFileTimestamp(now))-\(newThreadID).jsonl")

        var backups: [String] = []
        var changed: [String] = []
        backups += try backupStateFiles(stamp: "\(stamp)-branch")
        backups.append(try backup(sessionIndex, suffix: "\(stamp)-branch").path)

        let branchedContent = try branchContent(
            from: keptLines,
            newThreadID: newThreadID,
            timestamp: nowJSONL,
            cwd: thread.cwd
        )
        try fileManager.createDirectory(at: newRolloutURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        var insertedSQLiteRow = false
        do {
            try branchedContent.write(to: newRolloutURL, atomically: true, encoding: .utf8)
            changed.append(newRolloutURL.path)

            try insertBranchedSQLiteRow(
                sourceThreadID: thread.id,
                newThreadID: newThreadID,
                rolloutPath: newRolloutURL.path,
                title: newTitle,
                createdAt: nowSeconds,
                updatedAt: nowSeconds,
                createdAtMs: nowMs,
                updatedAtMs: nowMs
            )
            insertedSQLiteRow = true
            try verifyBranchedSQLiteRow(threadID: newThreadID)
            changed.append(stateDB.path)

            try appendSessionIndex(threadID: newThreadID, title: newTitle, updatedAt: nowIndex)
            changed.append(sessionIndex.path)
        } catch {
            if insertedSQLiteRow {
                try? deleteBranchedSQLiteRow(threadID: newThreadID)
            }
            if fileManager.fileExists(atPath: newRolloutURL.path) {
                try? fileManager.removeItem(at: newRolloutURL)
            }
            throw error
        }

        return BranchReport(
            sourceThreadID: thread.id,
            newThreadID: newThreadID,
            title: newTitle,
            createdFromLine: lineNumber,
            keptLineCount: keptLines.count,
            rolloutPath: newRolloutURL.path,
            timestamp: stamp,
            backups: backups,
            changedFiles: changed
        )
    }

    func move(thread: CodexThread, to project: ProjectSummary) throws -> MoveReport {
        guard !project.path.isEmpty else {
            throw WakeError.commandFailed("Cannot move to All Projects")
        }
        guard fileManager.fileExists(atPath: thread.rolloutPath) else {
            throw WakeError.missingThreadFile(thread.rolloutPath)
        }

        let stamp = backupStamp()
        let backupSuffix = "\(stamp)-move"
        var backups: [String] = []
        var changed: [String] = []

        backups += try backupStateFiles(stamp: backupSuffix)
        backups.append(try backup(thread.rolloutURL, suffix: backupSuffix).path)

        try updateSQLiteProject(threadID: thread.id, cwd: project.path)
        changed.append(stateDB.path)

        try updateSessionMetaProject(path: thread.rolloutURL, cwd: project.path)
        changed.append(thread.rolloutPath)

        return MoveReport(
            threadID: thread.id,
            fromProject: thread.cwd,
            toProject: project.path,
            timestamp: stamp,
            backups: backups,
            changedFiles: changed
        )
    }

    func moveThreadToTrash(_ thread: CodexThread) throws -> TrashThreadReport {
        let rolloutURL = thread.rolloutURL.standardizedFileURL
        let sessionsRoot = codexHome.appendingPathComponent("sessions", isDirectory: true).standardizedFileURL
        let fileExists = fileManager.fileExists(atPath: rolloutURL.path)
        if fileExists && !rolloutURL.path.hasPrefix(sessionsRoot.path + "/") {
            throw WakeError.commandFailed("Refusing to trash a chat file outside ~/.codex/sessions.")
        }

        let sqliteRecord = try loadFullThreadRecord(threadID: thread.id)
        let sessionIndexEntry = try loadSessionIndex()[thread.id]
        let stamp = backupStamp()
        let backupSuffix = "\(stamp)-trash-thread"
        var backups: [String] = []
        var changed: [String] = []

        backups += try backupStateFiles(stamp: backupSuffix)
        if fileManager.fileExists(atPath: sessionIndex.path) {
            backups.append(try backup(sessionIndex, suffix: backupSuffix).path)
        }

        var trashedPath: String?
        let trashDirectory = threadTrash.appendingPathComponent(thread.id, isDirectory: true)
        try fileManager.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
        if fileExists {
            let destination = uniqueTrashURL(for: rolloutURL.lastPathComponent, in: trashDirectory)
            try fileManager.moveItem(at: rolloutURL, to: destination)
            trashedPath = destination.path
            changed.append(thread.rolloutPath)
        }

        let manifest = TrashedThreadManifest(
            version: 1,
            threadID: thread.id,
            title: thread.shortTitle,
            originalPath: thread.rolloutPath,
            trashPath: trashedPath,
            cwd: thread.cwd,
            trashedAt: WakeDates.isoNowForJSONL(),
            sqliteRecord: sqliteRecord,
            sessionIndexEntry: sessionIndexEntry
        )
        try writeTrashManifest(manifest, to: trashDirectory.appendingPathComponent("manifest.json"))

        try deleteSQLiteThread(threadID: thread.id)
        changed.append(stateDB.path)

        if fileManager.fileExists(atPath: sessionIndex.path) {
            try removeSessionIndexEntry(threadID: thread.id)
            changed.append(sessionIndex.path)
        }

        return TrashThreadReport(
            threadID: thread.id,
            title: thread.shortTitle,
            rolloutPath: thread.rolloutPath,
            trashedPath: trashedPath,
            timestamp: stamp,
            backups: backups,
            changedFiles: changed
        )
    }

    func restoreTrashedThread(_ thread: TrashedThread) throws {
        let manifestURL = URL(fileURLWithPath: thread.manifestPath).standardizedFileURL
        guard manifestURL.path.hasPrefix(threadTrash.standardizedFileURL.path + "/") else {
            throw WakeError.commandFailed("Refusing to restore a chat outside Codex Wake trash.")
        }
        let manifest = try JSONDecoder().decode(TrashedThreadManifest.self, from: Data(contentsOf: manifestURL))
        let originalURL = URL(fileURLWithPath: manifest.originalPath).standardizedFileURL
        let sessionsRoot = codexHome.appendingPathComponent("sessions", isDirectory: true).standardizedFileURL
        guard originalURL.path.hasPrefix(sessionsRoot.path + "/") else {
            throw WakeError.commandFailed("Refusing to restore a chat outside ~/.codex/sessions.")
        }
        if fileManager.fileExists(atPath: originalURL.path) {
            throw WakeError.commandFailed("Original chat file already exists.")
        }

        _ = try backupStateFiles(stamp: "\(backupStamp())-before-trash-restore")
        if fileManager.fileExists(atPath: sessionIndex.path) {
            _ = try backup(sessionIndex, suffix: "\(backupStamp())-before-trash-restore")
        }
        try fileManager.createDirectory(at: originalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let trashPath = manifest.trashPath {
            let trashURL = URL(fileURLWithPath: trashPath).standardizedFileURL
            guard trashURL.path.hasPrefix(threadTrash.standardizedFileURL.path + "/"),
                  fileManager.fileExists(atPath: trashURL.path)
            else {
                throw WakeError.commandFailed("Trashed chat file is missing.")
            }
            try fileManager.copyItem(at: trashURL, to: originalURL)
        }

        try insertFullThreadRecord(manifest.sqliteRecord)
        if let entry = manifest.sessionIndexEntry {
            try appendSessionIndexEntry(entry)
        }
        try deleteTrashDirectory(containing: manifestURL)
    }

    func deleteTrashedThreadPermanently(_ thread: TrashedThread) throws {
        let manifestURL = URL(fileURLWithPath: thread.manifestPath).standardizedFileURL
        guard manifestURL.path.hasPrefix(threadTrash.standardizedFileURL.path + "/") else {
            throw WakeError.commandFailed("Refusing to delete a file outside Codex Wake trash.")
        }
        try deleteTrashDirectory(containing: manifestURL)
    }

    func emptyThreadTrash() throws -> Int {
        guard fileManager.fileExists(atPath: threadTrash.path) else { return 0 }
        let directories = try fileManager.contentsOfDirectory(
            at: threadTrash,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var removed = 0
        for directory in directories {
            let standardized = directory.standardizedFileURL
            guard standardized.path.hasPrefix(threadTrash.standardizedFileURL.path + "/") else { continue }
            let values = try? standardized.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            try fileManager.removeItem(at: standardized)
            removed += 1
        }
        return removed
    }

    private func loadThreadRows() throws -> [ThreadRow] {
        let query = """
        select id, rollout_path, created_at, updated_at, source, coalesce(thread_source, '') as thread_source,
               has_user_event, archived,
               substr(title, 1, 240) as title,
               substr(first_user_message, 1, 500) as first_user_message,
               substr(preview, 1, 500) as preview,
               cwd, created_at_ms, updated_at_ms
        from threads
        order by updated_at desc;
        """
        var database: OpaquePointer?
        guard sqlite3_open_v2(stateDB.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database
        else {
            throw WakeError.commandFailed("Cannot open SQLite database")
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            let message = String(cString: sqlite3_errmsg(database))
            throw WakeError.commandFailed("Cannot prepare SQLite query: \(message)")
        }
        defer { sqlite3_finalize(statement) }

        var rows: [ThreadRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(
                ThreadRow(
                    id: text(statement, 0),
                    rollout_path: text(statement, 1),
                    created_at: int64(statement, 2),
                    updated_at: int64(statement, 3),
                    source: text(statement, 4),
                    thread_source: text(statement, 5),
                    has_user_event: int(statement, 6),
                    archived: int(statement, 7),
                    title: text(statement, 8),
                    first_user_message: nullableText(statement, 9),
                    preview: nullableText(statement, 10),
                    cwd: text(statement, 11),
                    created_at_ms: int64(statement, 12),
                    updated_at_ms: int64(statement, 13)
                )
            )
        }
        return rows
    }

    private func backupKind(for originalName: String) -> BackupKind {
        if originalName == "state_5.sqlite" || originalName.hasPrefix("state_5.sqlite-") {
            return .stateDatabase
        }
        if originalName == "session_index.jsonl" {
            return .sessionIndex
        }
        if originalName.hasSuffix(".jsonl") {
            return .chatFile
        }
        return .other
    }

    private func backupReason(for stamp: String, kind: BackupKind) -> String {
        if stamp.contains("-trim") {
            return "Created before Trim from here"
        }
        if stamp.contains("-before-restore") {
            return "Created before Restore"
        }
        if stamp.contains("-wake") {
            return "Created before Repair Index"
        }
        if stamp.contains("-move") {
            return "Created before Move"
        }
        if kind == .chatFile {
            return "Created before a chat change (legacy backup)"
        }
        return "Created by Codex Wake"
    }

    private func isMainBackup(_ backup: BackupFile) -> Bool {
        guard backup.kind == .chatFile else { return false }
        if backup.stamp.contains("-wake") || backup.stamp.contains("-move") {
            return false
        }
        return true
    }

    private func backupChatTitle(from url: URL, sessionIndex: [String: SessionIndexEntry]) -> String? {
        guard let prefix = try? readPrefix(of: url, maxBytes: 512 * 1024) else { return nil }
        if let id = firstCapture(in: prefix, pattern: #""payload":\{"id":"([^"]+)""#),
           let title = sessionIndex[id]?.thread_name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title.oneLine.prefixString(100)
        }

        for line in prefix.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = extractMessage(
                    from: obj,
                    lineNumber: 0,
                    branchLineNumber: nil,
                    isTurnStart: false,
                    isSteered: false,
                    isFirstVisibleUserMessage: false
                  ),
                  message.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "user"
            else { continue }
            return message.text.oneLine.prefixString(100)
        }

        return nil
    }

    private func uniqueTrashURL(for fileName: String, in directory: URL) -> URL {
        var destination = directory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: destination.path) else { return destination }

        let suffix = backupStamp()
        destination = directory.appendingPathComponent("\(fileName).trashed-\(suffix)")
        var counter = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(fileName).trashed-\(suffix)-\(counter)")
            counter += 1
        }
        return destination
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: cString)
    }

    private func nullableText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return text(statement, index)
    }

    private func int(_ statement: OpaquePointer, _ index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int(statement, index))
    }

    private func int64(_ statement: OpaquePointer, _ index: Int32) -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(statement, index)
    }

    private func loadSessionIndex() throws -> [String: SessionIndexEntry] {
        guard fileManager.fileExists(atPath: sessionIndex.path) else { return [:] }
        let text = try String(contentsOf: sessionIndex, encoding: .utf8)
        var result: [String: SessionIndexEntry] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8),
                  let entry = try? JSONDecoder().decode(SessionIndexEntry.self, from: data)
            else { continue }
            result[entry.id] = entry
        }
        return result
    }

    private func loadSessionMeta(path: String) -> SessionMetaLine? {
        guard fileManager.fileExists(atPath: path) else { return nil }
        guard let prefix = try? readPrefix(of: URL(fileURLWithPath: path), maxBytes: 64 * 1024) else { return nil }
        return SessionMetaLine(
            timestamp: firstCapture(in: prefix, pattern: #"^\{"timestamp":"([^"]+)""#),
            payload: .init(
                id: firstCapture(in: prefix, pattern: #""payload":\{"id":"([^"]+)""#),
                timestamp: firstCapture(in: prefix, pattern: #""payload":\{"id":"[^"]+","timestamp":"([^"]+)""#),
                cwd: firstCapture(in: prefix, pattern: #""cwd":"([^"]+)""#),
                source: firstCapture(in: prefix, pattern: #""source":"([^"]+)""#)
            )
        )
    }

    private func readPrefix(of url: URL, maxBytes: Int) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = handle.readData(ofLength: maxBytes)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    private func extractMessage(
        from obj: [String: Any],
        lineNumber: Int,
        branchLineNumber: Int?,
        isTurnStart: Bool,
        isSteered: Bool,
        isFirstVisibleUserMessage: Bool
    ) -> PreviewMessage? {
        let timestamp = obj["timestamp"] as? String
        guard let payload = obj["payload"] as? [String: Any] else { return nil }

        if let type = payload["type"] as? String, type == "message" {
            let role = payload["role"] as? String ?? "message"
            if role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "developer" {
                return nil
            }
            let text = cleanPreviewText(extractContentText(payload["content"]))
            if !text.isEmpty {
                return PreviewMessage(
                    role: role,
                    text: text,
                    timestamp: timestamp,
                    lineNumber: lineNumber,
                    branchLineNumber: branchLineNumber,
                    isTurnStart: isTurnStart,
                    isSteered: isSteered,
                    isFirstVisibleUserMessage: role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "user" && isFirstVisibleUserMessage
                )
            }
        }

        if let type = obj["type"] as? String, type == "user_message",
           let text = payload["message"] as? String {
            let cleanedText = cleanPreviewText(text)
            if !cleanedText.isEmpty {
                return PreviewMessage(
                    role: "user",
                    text: cleanedText,
                    timestamp: timestamp,
                    lineNumber: lineNumber,
                    branchLineNumber: branchLineNumber,
                    isTurnStart: isTurnStart,
                    isSteered: isSteered,
                    isFirstVisibleUserMessage: isFirstVisibleUserMessage
                )
            }
        }

        return nil
    }

    private func isUserObject(_ obj: [String: Any]) -> Bool {
        let payload = obj["payload"] as? [String: Any]
        if obj["type"] as? String == "user_message" {
            return true
        }
        return (payload?["type"] as? String) == "message" && (payload?["role"] as? String) == "user"
    }

    private func extractContentText(_ value: Any?) -> String {
        if let text = value as? String { return text }
        guard let array = value as? [[String: Any]] else { return "" }
        return array.compactMap { item in
            if let text = item["text"] as? String { return text }
            if let text = item["content"] as? String { return text }
            return nil
        }.joined(separator: "\n")
    }

    private func cleanPreviewText(_ text: String) -> String {
        var result = text
        result = removing(pattern: #"<permissions instructions>.*?</permissions instructions>\s*"#, from: result)
        result = removing(pattern: #"# AGENTS\.md instructions[^\n]*(?:\n|\r\n).*?</INSTRUCTIONS>\s*"#, from: result)
        result = removing(pattern: #"\n{3,}"#, from: result, replacingWith: "\n\n")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func removing(pattern: String, from text: String, replacingWith replacement: String = "") -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }

    private func backupStateFiles(stamp: String) throws -> [String] {
        let names = ["state_5.sqlite", "state_5.sqlite-wal", "state_5.sqlite-shm"]
        var paths: [String] = []
        for name in names {
            let url = codexHome.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                paths.append(try backup(url, suffix: stamp).path)
            }
        }
        return paths
    }

    private func backup(_ url: URL, suffix: String) throws -> URL {
        let destination = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".codex-rescue-backup-" + suffix)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: url, to: destination)
        return destination
    }

    private func writeTrashManifest(_ manifest: TrashedThreadManifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    private func deleteTrashDirectory(containing manifestURL: URL) throws {
        let directory = manifestURL.deletingLastPathComponent().standardizedFileURL
        guard directory.path.hasPrefix(threadTrash.standardizedFileURL.path + "/") else {
            throw WakeError.commandFailed("Refusing to delete a file outside Codex Wake trash.")
        }
        try fileManager.removeItem(at: directory)
    }

    private func updateSQLite(threadID: String, updatedAt: Int64, updatedAtMs: Int64) throws {
        let sql = """
        update threads
        set thread_source = 'user', updated_at = \(updatedAt), updated_at_ms = \(updatedAtMs)
        where id = '\(threadID.replacingOccurrences(of: "'", with: "''"))';
        """
        _ = try Shell.run("/usr/bin/sqlite3", [stateDB.path, sql])
    }

    private func updateSQLiteProject(threadID: String, cwd: String) throws {
        let escapedThreadID = threadID.replacingOccurrences(of: "'", with: "''")
        let escapedCWD = cwd.replacingOccurrences(of: "'", with: "''")
        let sql = """
        update threads
        set cwd = '\(escapedCWD)'
        where id = '\(escapedThreadID)';
        """
        _ = try Shell.run("/usr/bin/sqlite3", [stateDB.path, sql])
    }

    private func deleteSQLiteThread(threadID: String) throws {
        _ = try Shell.run(
            "/usr/bin/sqlite3",
            [stateDB.path, "delete from threads where id = '\(sql(threadID))';"]
        )
    }

    private func loadFullThreadRecord(threadID: String) throws -> ThreadSQLiteRecord {
        let query = """
        select id, rollout_path, created_at, updated_at, source, model_provider, cwd, title,
               sandbox_policy, approval_mode, tokens_used, has_user_event, archived, archived_at,
               git_sha, git_branch, git_origin_url, cli_version, first_user_message,
               agent_nickname, agent_role, memory_mode, model, reasoning_effort, agent_path,
               created_at_ms, updated_at_ms, thread_source, preview
        from threads
        where id = '\(sql(threadID))';
        """
        var database: OpaquePointer?
        guard sqlite3_open_v2(stateDB.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database
        else {
            throw WakeError.commandFailed("Cannot open SQLite database")
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            let message = String(cString: sqlite3_errmsg(database))
            throw WakeError.commandFailed("Cannot prepare SQLite query: \(message)")
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw WakeError.commandFailed("Thread metadata not found in Codex state database.")
        }

        return ThreadSQLiteRecord(
            id: text(statement, 0),
            rolloutPath: text(statement, 1),
            createdAt: int64(statement, 2) ?? 0,
            updatedAt: int64(statement, 3) ?? 0,
            source: text(statement, 4),
            modelProvider: text(statement, 5),
            cwd: text(statement, 6),
            title: text(statement, 7),
            sandboxPolicy: text(statement, 8),
            approvalMode: text(statement, 9),
            tokensUsed: int64(statement, 10) ?? 0,
            hasUserEvent: int64(statement, 11) ?? 0,
            archived: int64(statement, 12) ?? 0,
            archivedAt: int64(statement, 13),
            gitSHA: nullableText(statement, 14),
            gitBranch: nullableText(statement, 15),
            gitOriginURL: nullableText(statement, 16),
            cliVersion: text(statement, 17),
            firstUserMessage: text(statement, 18),
            agentNickname: nullableText(statement, 19),
            agentRole: nullableText(statement, 20),
            memoryMode: text(statement, 21),
            model: nullableText(statement, 22),
            reasoningEffort: nullableText(statement, 23),
            agentPath: nullableText(statement, 24),
            createdAtMs: int64(statement, 25),
            updatedAtMs: int64(statement, 26),
            threadSource: nullableText(statement, 27),
            preview: text(statement, 28)
        )
    }

    private func insertFullThreadRecord(_ record: ThreadSQLiteRecord) throws {
        let existing = try Shell.run(
            "/usr/bin/sqlite3",
            [stateDB.path, "select count(*) from threads where id = '\(sql(record.id))';"]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard existing == "0" else {
            throw WakeError.commandFailed("Thread metadata already exists in Codex state database.")
        }

        let statementSQL = """
        insert into threads (
            id, rollout_path, created_at, updated_at, source, model_provider, cwd, title,
            sandbox_policy, approval_mode, tokens_used, has_user_event, archived, archived_at,
            git_sha, git_branch, git_origin_url, cli_version, first_user_message,
            agent_nickname, agent_role, memory_mode, model, reasoning_effort, agent_path,
            created_at_ms, updated_at_ms, thread_source, preview
        ) values (
            \(sqlValue(record.id)),
            \(sqlValue(record.rolloutPath)),
            \(record.createdAt),
            \(record.updatedAt),
            \(sqlValue(record.source)),
            \(sqlValue(record.modelProvider)),
            \(sqlValue(record.cwd)),
            \(sqlValue(record.title)),
            \(sqlValue(record.sandboxPolicy)),
            \(sqlValue(record.approvalMode)),
            \(record.tokensUsed),
            \(record.hasUserEvent),
            \(record.archived),
            \(sqlValue(record.archivedAt)),
            \(sqlValue(record.gitSHA)),
            \(sqlValue(record.gitBranch)),
            \(sqlValue(record.gitOriginURL)),
            \(sqlValue(record.cliVersion)),
            \(sqlValue(record.firstUserMessage)),
            \(sqlValue(record.agentNickname)),
            \(sqlValue(record.agentRole)),
            \(sqlValue(record.memoryMode)),
            \(sqlValue(record.model)),
            \(sqlValue(record.reasoningEffort)),
            \(sqlValue(record.agentPath)),
            \(sqlValue(record.createdAtMs)),
            \(sqlValue(record.updatedAtMs)),
            \(sqlValue(record.threadSource)),
            \(sqlValue(record.preview))
        );
        """
        _ = try Shell.run("/usr/bin/sqlite3", [stateDB.path, statementSQL])
    }

    private func updateSessionIndex(threadID: String, updatedAt: String) throws {
        guard fileManager.fileExists(atPath: sessionIndex.path) else { return }
        let text = try String(contentsOf: sessionIndex, encoding: .utf8)
        var lines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty { continue }
            guard let data = String(line).data(using: .utf8),
                  var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                lines.append(String(line))
                continue
            }
            if obj["id"] as? String == threadID {
                obj["updated_at"] = updatedAt
                let encoded = try JSONSerialization.data(withJSONObject: obj, options: [])
                lines.append(String(data: encoded, encoding: .utf8) ?? String(line))
            } else {
                lines.append(String(line))
            }
        }
        try (lines.joined(separator: "\n") + "\n").write(to: sessionIndex, atomically: true, encoding: .utf8)
    }

    private func removeSessionIndexEntry(threadID: String) throws {
        guard fileManager.fileExists(atPath: sessionIndex.path) else { return }
        let text = try String(contentsOf: sessionIndex, encoding: .utf8)
        var lines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty { continue }
            guard let data = String(line).data(using: .utf8),
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["id"] as? String == threadID
            else {
                lines.append(String(line))
                continue
            }
        }
        try (lines.joined(separator: "\n") + "\n").write(to: sessionIndex, atomically: true, encoding: .utf8)
    }

    private func appendSessionIndex(threadID: String, title: String, updatedAt: String) throws {
        guard fileManager.fileExists(atPath: sessionIndex.path) else { return }
        let obj: [String: String] = [
            "id": threadID,
            "thread_name": title,
            "updated_at": updatedAt
        ]
        let encoded = try JSONSerialization.data(withJSONObject: obj, options: [])
        guard let line = String(data: encoded, encoding: .utf8) else {
            throw WakeError.invalidJSON("Cannot encode session index line")
        }
        let existing = try String(contentsOf: sessionIndex, encoding: .utf8)
        let separator = existing.hasSuffix("\n") || existing.isEmpty ? "" : "\n"
        let handle = try FileHandle(forWritingTo: sessionIndex)
        defer { try? handle.close() }
        try handle.seekToEnd()
        if let data = (separator + line + "\n").data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    }

    private func appendSessionIndexEntry(_ entry: SessionIndexEntry) throws {
        guard fileManager.fileExists(atPath: sessionIndex.path) else { return }
        if try loadSessionIndex()[entry.id] != nil { return }
        var obj: [String: String] = ["id": entry.id]
        if let threadName = entry.thread_name {
            obj["thread_name"] = threadName
        }
        if let updatedAt = entry.updated_at {
            obj["updated_at"] = updatedAt
        }
        let encoded = try JSONSerialization.data(withJSONObject: obj, options: [])
        guard let line = String(data: encoded, encoding: .utf8) else {
            throw WakeError.invalidJSON("Cannot encode session index line")
        }
        let existing = try String(contentsOf: sessionIndex, encoding: .utf8)
        let separator = existing.hasSuffix("\n") || existing.isEmpty ? "" : "\n"
        let handle = try FileHandle(forWritingTo: sessionIndex)
        defer { try? handle.close() }
        try handle.seekToEnd()
        if let data = (separator + line + "\n").data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    }

    private func updateSessionMeta(path: URL, timestamp: String) throws {
        let text = try String(contentsOf: path, encoding: .utf8)
        let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first,
              let data = String(first).data(using: .utf8),
              var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw WakeError.invalidJSON("Cannot decode first JSONL line") }

        obj["timestamp"] = timestamp
        var payload = obj["payload"] as? [String: Any] ?? [:]
        payload["timestamp"] = timestamp
        obj["payload"] = payload

        let encoded = try JSONSerialization.data(withJSONObject: obj, options: [])
        let firstLine = String(data: encoded, encoding: .utf8) ?? String(first)
        let rest = parts.count > 1 ? String(parts[1]) : ""
        try (firstLine + "\n" + rest).write(to: path, atomically: true, encoding: .utf8)
    }

    private func branchContent(from lines: [String], newThreadID: String, timestamp: String, cwd: String) throws -> String {
        guard let first = lines.first,
              let data = first.data(using: .utf8),
              var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw WakeError.invalidJSON("Cannot decode first JSONL line") }

        obj["timestamp"] = timestamp
        var payload = obj["payload"] as? [String: Any] ?? [:]
        payload["id"] = newThreadID
        payload["timestamp"] = timestamp
        payload["cwd"] = cwd
        payload["thread_source"] = "user"
        obj["payload"] = payload

        let encoded = try JSONSerialization.data(withJSONObject: obj, options: [])
        guard let firstLine = String(data: encoded, encoding: .utf8) else {
            throw WakeError.invalidJSON("Cannot encode branched session meta")
        }

        var result = [firstLine]
        result.append(contentsOf: lines.dropFirst())
        return result.joined(separator: "\n") + "\n"
    }

    private func updateSessionMetaProject(path: URL, cwd: String) throws {
        let text = try String(contentsOf: path, encoding: .utf8)
        let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first,
              let data = String(first).data(using: .utf8),
              var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw WakeError.invalidJSON("Cannot decode first JSONL line") }

        var payload = obj["payload"] as? [String: Any] ?? [:]
        payload["cwd"] = cwd
        obj["payload"] = payload

        let encoded = try JSONSerialization.data(withJSONObject: obj, options: [])
        let firstLine = String(data: encoded, encoding: .utf8) ?? String(first)
        let rest = parts.count > 1 ? String(parts[1]) : ""
        try (firstLine + "\n" + rest).write(to: path, atomically: true, encoding: .utf8)
    }

    private func insertBranchedSQLiteRow(
        sourceThreadID: String,
        newThreadID: String,
        rolloutPath: String,
        title: String,
        createdAt: Int64,
        updatedAt: Int64,
        createdAtMs: Int64,
        updatedAtMs: Int64
    ) throws {
        let sourceID = sql(sourceThreadID)
        let statementSQL = """
        insert into threads (
            id, rollout_path, created_at, updated_at, source, model_provider, cwd, title,
            sandbox_policy, approval_mode, tokens_used, has_user_event, archived, archived_at,
            git_sha, git_branch, git_origin_url, cli_version, first_user_message,
            agent_nickname, agent_role, memory_mode, model, reasoning_effort, agent_path,
            created_at_ms, updated_at_ms, thread_source, preview
        )
        select
            '\(sql(newThreadID))',
            '\(sql(rolloutPath))',
            \(createdAt),
            \(updatedAt),
            source,
            model_provider,
            cwd,
            '\(sql(title))',
            sandbox_policy,
            approval_mode,
            0,
            has_user_event,
            0,
            NULL,
            git_sha,
            git_branch,
            git_origin_url,
            cli_version,
            first_user_message,
            agent_nickname,
            agent_role,
            memory_mode,
            model,
            reasoning_effort,
            agent_path,
            \(createdAtMs),
            \(updatedAtMs),
            'user',
            preview
        from threads
        where id = '\(sourceID)';
        """
        _ = try Shell.run("/usr/bin/sqlite3", [stateDB.path, statementSQL])
    }

    private func verifyBranchedSQLiteRow(threadID: String) throws {
        let output = try Shell.run(
            "/usr/bin/sqlite3",
            [stateDB.path, "select count(*) from threads where id = '\(sql(threadID))';"]
        )
        guard output.trimmingCharacters(in: .whitespacesAndNewlines) == "1" else {
            throw WakeError.commandFailed("Branch was not registered in the Codex state database.")
        }
    }

    private func deleteBranchedSQLiteRow(threadID: String) throws {
        _ = try Shell.run(
            "/usr/bin/sqlite3",
            [stateDB.path, "delete from threads where id = '\(sql(threadID))';"]
        )
    }

    private func branchTitle(for thread: CodexThread) -> String {
        "Branch: \(thread.shortTitle)".prefixString(240)
    }

    private func branchDatePath(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }

    private func branchFileTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return formatter.string(from: date)
    }

    private func uniqueThreadID() throws -> String {
        var id = makeUUIDv7()
        var attempts = 0
        while fileManager.fileExists(atPath: codexHome.appendingPathComponent("sessions").appendingPathComponent(id).path) {
            id = makeUUIDv7()
            attempts += 1
            if attempts > 10 {
                throw WakeError.commandFailed("Could not generate a unique thread id.")
            }
        }
        return id
    }

    private func makeUUIDv7() -> String {
        let timestampMs = UInt64(Date().timeIntervalSince1970 * 1000)
        var bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        bytes[0] = UInt8((timestampMs >> 40) & 0xff)
        bytes[1] = UInt8((timestampMs >> 32) & 0xff)
        bytes[2] = UInt8((timestampMs >> 24) & 0xff)
        bytes[3] = UInt8((timestampMs >> 16) & 0xff)
        bytes[4] = UInt8((timestampMs >> 8) & 0xff)
        bytes[5] = UInt8(timestampMs & 0xff)
        bytes[6] = (bytes[6] & 0x0f) | 0x70
        bytes[8] = (bytes[8] & 0x3f) | 0x80

        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return [
            String(hex.prefix(8)),
            String(hex.dropFirst(8).prefix(4)),
            String(hex.dropFirst(12).prefix(4)),
            String(hex.dropFirst(16).prefix(4)),
            String(hex.dropFirst(20).prefix(12))
        ].joined(separator: "-")
    }

    private func sql(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private func sqlValue(_ value: String?) -> String {
        guard let value else { return "NULL" }
        return "'\(sql(value))'"
    }

    private func sqlValue(_ value: Int64?) -> String {
        guard let value else { return "NULL" }
        return "\(value)"
    }

    private func backupStamp() -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

private struct ThreadRow: Decodable {
    let id: String
    let rollout_path: String
    let created_at: Int64?
    let updated_at: Int64?
    let source: String
    let thread_source: String?
    let has_user_event: Int?
    let archived: Int?
    let title: String
    let first_user_message: String?
    let preview: String?
    let cwd: String
    let created_at_ms: Int64?
    let updated_at_ms: Int64?
}

private struct SessionIndexEntry: Codable {
    let id: String
    let thread_name: String?
    let updated_at: String?
}

private struct TrashedThreadManifest: Codable {
    let version: Int
    let threadID: String
    let title: String
    let originalPath: String
    let trashPath: String?
    let cwd: String
    let trashedAt: String
    let sqliteRecord: ThreadSQLiteRecord
    let sessionIndexEntry: SessionIndexEntry?
}

private struct ThreadSQLiteRecord: Codable {
    let id: String
    let rolloutPath: String
    let createdAt: Int64
    let updatedAt: Int64
    let source: String
    let modelProvider: String
    let cwd: String
    let title: String
    let sandboxPolicy: String
    let approvalMode: String
    let tokensUsed: Int64
    let hasUserEvent: Int64
    let archived: Int64
    let archivedAt: Int64?
    let gitSHA: String?
    let gitBranch: String?
    let gitOriginURL: String?
    let cliVersion: String
    let firstUserMessage: String
    let agentNickname: String?
    let agentRole: String?
    let memoryMode: String
    let model: String?
    let reasoningEffort: String?
    let agentPath: String?
    let createdAtMs: Int64?
    let updatedAtMs: Int64?
    let threadSource: String?
    let preview: String
}

private struct SessionMetaLine: Decodable {
    let timestamp: String?
    let payload: Payload?

    struct Payload: Decodable {
        let id: String?
        let timestamp: String?
        let cwd: String?
        let source: String?
    }
}
