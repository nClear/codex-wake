import Foundation
import SQLite3

final class CodexStore: ThreadStore, @unchecked Sendable {
    private let fileManager = FileManager.default
    private let codexHome: URL
    private let stateDB: URL
    private let sessionIndex: URL

    init(codexHome: URL? = nil) {
        let home = codexHome ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        self.codexHome = home
        self.stateDB = home.appendingPathComponent("state_5.sqlite")
        self.sessionIndex = home.appendingPathComponent("session_index.jsonl")
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

        let marker = ".codex-rescue-backup-"
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(
            at: codexHome,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var backups: [BackupFile] = []
        for case let url as URL in enumerator {
            let fileName = url.lastPathComponent
            guard let markerRange = fileName.range(of: marker) else { continue }

            let originalName = String(fileName[..<markerRange.lowerBound])
            let stamp = String(fileName[markerRange.upperBound...])
            guard !originalName.isEmpty, !stamp.isEmpty else { continue }

            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == false { continue }

            let directoryURL = url.deletingLastPathComponent()
            let originalURL = directoryURL.appendingPathComponent(originalName)
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
                    kind: backupKind(for: originalName),
                    originalExists: fileManager.fileExists(atPath: originalURL.path)
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

    func loadPreview(for thread: CodexThread) throws -> ThreadPreview {
        guard fileManager.fileExists(atPath: thread.rolloutPath) else {
            throw WakeError.missingThreadFile(thread.rolloutPath)
        }

        let content = try readPrefix(of: URL(fileURLWithPath: thread.rolloutPath), maxBytes: 2 * 1024 * 1024)
        var messages: [PreviewMessage] = []
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard messages.count < 40,
                  let data = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if let message = extractMessage(from: obj) {
                messages.append(message)
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
        var backups: [String] = []
        var changed: [String] = []

        backups += try backupStateFiles(stamp: stamp)
        backups.append(try backup(sessionIndex, suffix: stamp).path)
        backups.append(try backup(thread.rolloutURL, suffix: stamp).path)

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

    func move(thread: CodexThread, to project: ProjectSummary) throws -> MoveReport {
        guard !project.path.isEmpty else {
            throw WakeError.commandFailed("Cannot move to All Projects")
        }
        guard fileManager.fileExists(atPath: thread.rolloutPath) else {
            throw WakeError.missingThreadFile(thread.rolloutPath)
        }

        let stamp = backupStamp()
        var backups: [String] = []
        var changed: [String] = []

        backups += try backupStateFiles(stamp: stamp)
        backups.append(try backup(thread.rolloutURL, suffix: stamp).path)

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

    private func extractMessage(from obj: [String: Any]) -> PreviewMessage? {
        let timestamp = obj["timestamp"] as? String
        guard let payload = obj["payload"] as? [String: Any] else { return nil }

        if let type = payload["type"] as? String, type == "message" {
            let role = payload["role"] as? String ?? "message"
            let text = cleanPreviewText(extractContentText(payload["content"]))
            if !text.isEmpty { return PreviewMessage(role: role, text: text.prefixString(1200), timestamp: timestamp) }
        }

        if let type = obj["type"] as? String, type == "user_message",
           let text = payload["message"] as? String {
            let cleanedText = cleanPreviewText(text)
            if !cleanedText.isEmpty { return PreviewMessage(role: "user", text: cleanedText.prefixString(1200), timestamp: timestamp) }
        }

        return nil
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

private struct SessionIndexEntry: Decodable {
    let id: String
    let thread_name: String?
    let updated_at: String?
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
