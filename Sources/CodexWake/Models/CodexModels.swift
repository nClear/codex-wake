import Foundation

struct CodexThread: Identifiable, Hashable {
    let id: String
    let rolloutPath: String
    let createdAt: Date
    let updatedAt: Date
    let createdAtMs: Date?
    let updatedAtMs: Date?
    let source: String
    let threadSource: String
    let hasUserEvent: Bool
    let archived: Bool
    let title: String
    let sessionIndexTitle: String
    let firstUserMessage: String
    let preview: String
    let cwd: String
    let isInSessionIndex: Bool
    let sessionIndexUpdatedAt: Date?
    let sessionMetaTimestamp: Date?
    let sessionPayloadTimestamp: Date?
    let fileExists: Bool

    var rolloutURL: URL { URL(fileURLWithPath: rolloutPath) }
    var shortTitle: String {
        for candidate in [sessionIndexTitle, title, firstUserMessage] {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed.oneLine.prefixString(80) }
        }
        return id
    }

    var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent.isEmpty ? cwd : URL(fileURLWithPath: cwd).lastPathComponent
    }

    var needsWake: Bool {
        if archived { return false }
        if !fileExists { return false }
        if !isInSessionIndex { return true }
        return !isRecentlyUpdated
    }

    var isShown: Bool {
        !archived && fileExists && isInSessionIndex && isRecentlyUpdated
    }

    var isRecentlyUpdated: Bool {
        Date().timeIntervalSince(updatedAt) < 8 * 24 * 60 * 60
    }

    var statusLabel: String {
        if archived { return "Archived" }
        if !fileExists { return "Missing file" }
        if !isInSessionIndex { return "Hidden" }
        if needsWake { return "Old" }
        return "Shown"
    }

    func matchesMetadata(_ query: String) -> Bool {
        let q = query.lowercased()
        return id.lowercased().contains(q)
            || sessionIndexTitle.lowercased().contains(q)
            || title.lowercased().contains(q)
            || firstUserMessage.lowercased().contains(q)
            || preview.lowercased().contains(q)
            || cwd.lowercased().contains(q)
            || rolloutPath.lowercased().contains(q)
    }
}

struct ProjectSummary: Identifiable, Hashable {
    static let allID = "__all__"
    static let all = ProjectSummary(id: allID, name: "All Projects", path: "", totalCount: 0, hiddenCount: 0, shownCount: 0)

    let id: String
    let name: String
    let path: String
    let totalCount: Int
    let hiddenCount: Int
    let shownCount: Int

    static func make(from threads: [CodexThread]) -> [ProjectSummary] {
        let grouped = Dictionary(grouping: threads, by: \.cwd)
        let projects = grouped.map { cwd, items in
            ProjectSummary(
                id: cwd,
                name: URL(fileURLWithPath: cwd).lastPathComponent.isEmpty ? cwd : URL(fileURLWithPath: cwd).lastPathComponent,
                path: cwd,
                totalCount: items.count,
                hiddenCount: items.filter(\.needsWake).count,
                shownCount: items.filter(\.isShown).count
            )
        }
        .sorted { lhs, rhs in
            if lhs.hiddenCount != rhs.hiddenCount { return lhs.hiddenCount > rhs.hiddenCount }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        let all = ProjectSummary(
            id: allID,
            name: "All Projects",
            path: "",
            totalCount: threads.count,
            hiddenCount: threads.filter(\.needsWake).count,
            shownCount: threads.filter(\.isShown).count
        )
        return [all] + projects
    }
}

struct ThreadPreview: Identifiable {
    var id: String { threadID }
    let threadID: String
    let messages: [PreviewMessage]
    let rawError: String?
}

struct PreviewMessage: Identifiable, Hashable {
    let id: String
    let role: String
    let text: String
    let timestamp: String?

    var isContextMessage: Bool {
        let normalizedRole = role.lowercased()
        let normalizedText = text.lowercased()
        return normalizedRole == "developer"
            || normalizedRole == "system"
            || normalizedText.hasPrefix("<environment_context>")
            || normalizedText.hasPrefix("<permissions instructions>")
            || normalizedText.hasPrefix("<app-context>")
    }

    func withID(_ id: String) -> PreviewMessage {
        PreviewMessage(id: id, role: role, text: text, timestamp: timestamp)
    }
}

struct WakeReport: Identifiable {
    let id = UUID()
    let threadID: String
    let timestamp: String
    let backups: [String]
    let changedFiles: [String]
}

struct MoveReport: Identifiable {
    let id = UUID()
    let threadID: String
    let fromProject: String
    let toProject: String
    let timestamp: String
    let backups: [String]
    let changedFiles: [String]
}

struct OperationReport: Identifiable {
    let id = UUID()
    let title: String
    let threadIDs: Set<String>
    let timestamp: String
    let summary: String
    let backups: [String]
    let changedFiles: [String]
    let failures: [String]
}

struct BackupFile: Identifiable, Hashable {
    var id: String { path }

    let path: String
    let originalName: String
    let directory: String
    let stamp: String
    let size: Int64
    let modifiedAt: Date

    var url: URL { URL(fileURLWithPath: path) }

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

extension String {
    var oneLine: String {
        replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
    }

    func prefixString(_ count: Int) -> String {
        if self.count <= count { return self }
        return String(prefix(count)) + "..."
    }
}
