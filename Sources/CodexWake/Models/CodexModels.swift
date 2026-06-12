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
            if !trimmed.isEmpty {
                return trimmed.oneLine.prefixString(80)
            }
        }
        return id
    }

    var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent.isEmpty ? cwd : URL(fileURLWithPath: cwd).lastPathComponent
    }

    var needsRepair: Bool {
        if archived { return false }
        if !fileExists { return false }
        return !isInSessionIndex
    }

    var isAvailable: Bool {
        !archived && fileExists && isInSessionIndex
    }

    var statusLabel: String {
        if archived { return "Archived" }
        if !fileExists { return "Missing file" }
        if !isInSessionIndex { return "Not indexed" }
        return "Available"
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
    static let all = ProjectSummary(id: allID, name: "All Projects", path: "", totalCount: 0, repairCount: 0, availableCount: 0, latestUpdatedAt: nil)

    let id: String
    let name: String
    let path: String
    let totalCount: Int
    let repairCount: Int
    let availableCount: Int
    let latestUpdatedAt: Date?

    static func make(from threads: [CodexThread], sort: ProjectSortMode = .recent) -> [ProjectSummary] {
        let grouped = Dictionary(grouping: threads, by: \.cwd)
        let projects = grouped.map { cwd, items in
            ProjectSummary(
                id: cwd,
                name: URL(fileURLWithPath: cwd).lastPathComponent.isEmpty ? cwd : URL(fileURLWithPath: cwd).lastPathComponent,
                path: cwd,
                totalCount: items.count,
                repairCount: items.filter(\.needsRepair).count,
                availableCount: items.filter(\.isAvailable).count,
                latestUpdatedAt: items.map(\.updatedAt).max()
            )
        }
        .sorted { lhs, rhs in
            switch sort {
            case .recent:
                let lhsDate = lhs.latestUpdatedAt ?? .distantPast
                let rhsDate = rhs.latestUpdatedAt ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .name:
                let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if order != .orderedSame { return order == .orderedAscending }
                return (lhs.latestUpdatedAt ?? .distantPast) > (rhs.latestUpdatedAt ?? .distantPast)
            }
        }
        let all = ProjectSummary(
            id: allID,
            name: "All Projects",
            path: "",
            totalCount: threads.count,
            repairCount: threads.filter(\.needsRepair).count,
            availableCount: threads.filter(\.isAvailable).count,
            latestUpdatedAt: threads.map(\.updatedAt).max()
        )
        return [all] + projects
    }
}

enum ProjectSortMode: String, CaseIterable, Identifiable {
    case recent
    case name

    var id: String { rawValue }
}

enum AppSection {
    case chats
    case backups
    case backupTrash
}

struct ThreadPreview: Identifiable {
    var id: String { threadID }
    let threadID: String
    let messages: [PreviewMessage]
    let rawError: String?
}

struct PreviewMessage: Identifiable, Hashable {
    let id = UUID()
    let role: String
    let text: String
    let timestamp: String?
    let lineNumber: Int?
    let branchLineNumber: Int?
    let isTurnStart: Bool
    let isSteered: Bool
    let isFirstVisibleUserMessage: Bool

    var canTrimFromHere: Bool {
        (lineNumber ?? 0) > 1 && !isFirstVisibleUserMessage
    }

    var canBranchFromHere: Bool {
        isTurnStart && (branchLineNumber ?? 0) > 2
    }
}

struct WakeReport: Identifiable {
    let id = UUID()
    let threadID: String
    let timestamp: String
    let backups: [String]
    let changedFiles: [String]
}

struct TrimReport: Identifiable {
    let id = UUID()
    let threadID: String
    let timestamp: String
    let deletedFromLine: Int
    let removedLineCount: Int
    let backups: [String]
    let changedFiles: [String]
}

struct BranchReport: Identifiable {
    let id = UUID()
    let sourceThreadID: String
    let newThreadID: String
    let title: String
    let createdFromLine: Int
    let keptLineCount: Int
    let rolloutPath: String
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

struct TrashThreadReport: Identifiable {
    let id = UUID()
    let threadID: String
    let title: String
    let rolloutPath: String
    let trashedPath: String?
    let timestamp: String
    let backups: [String]
    let changedFiles: [String]
}

struct BatchWakeReport: Identifiable {
    let id = UUID()
    let completedAt: Date
    let requestedCount: Int
    let succeeded: [BatchWakeSuccess]
    let skipped: [BatchWakeSkipped]
    let failed: [BatchWakeFailure]

    var backupCount: Int {
        succeeded.reduce(0) { $0 + $1.backupCount }
    }
}

struct BatchWakeSuccess: Identifiable, Hashable {
    let threadID: String
    let title: String
    let backupCount: Int

    var id: String { threadID }
}

struct BatchWakeSkipped: Identifiable, Hashable {
    let threadID: String
    let title: String
    let reason: String

    var id: String { threadID }
}

struct BatchWakeFailure: Identifiable, Hashable {
    let threadID: String
    let title: String
    let message: String

    var id: String { threadID }
}

struct BackupFile: Identifiable, Hashable {
    var id: String { backupPath }

    let backupPath: String
    let originalPath: String
    let originalName: String
    let directory: String
    let stamp: String
    let createdAt: Date?
    let modifiedAt: Date?
    let size: Int64
    let kind: BackupKind
    let originalExists: Bool
    let chatTitle: String?
    let reason: String
}

struct TrashedThread: Identifiable, Hashable {
    var id: String { threadID }

    let threadID: String
    let title: String
    let originalPath: String
    let trashPath: String?
    let manifestPath: String
    let cwd: String
    let trashedAt: Date?
    let size: Int64
    let originalExists: Bool
}

enum BackupKind: String, Hashable {
    case stateDatabase
    case sessionIndex
    case chatFile
    case other

    var label: String {
        switch self {
        case .stateDatabase: return "State DB"
        case .sessionIndex: return "Session index"
        case .chatFile: return "Chat file"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .stateDatabase: return "cylinder.split.1x2"
        case .sessionIndex: return "list.bullet.rectangle"
        case .chatFile: return "text.bubble"
        case .other: return "doc"
        }
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
