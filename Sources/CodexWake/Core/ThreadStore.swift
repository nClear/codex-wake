import Foundation

protocol ThreadStore: Sendable {
    func loadThreads() throws -> [CodexThread]
    func loadBackups() throws -> [BackupFile]
    func loadBackupTrash() throws -> [BackupFile]
    func loadPreview(for thread: CodexThread) throws -> ThreadPreview
    func threadContainsRawText(_ thread: CodexThread, query: String) throws -> Bool
    func wake(thread: CodexThread) throws -> WakeReport
    func move(thread: CodexThread, to project: ProjectSummary) throws -> MoveReport
    func moveBackupToTrash(_ backup: BackupFile) throws
    func emptyBackupTrash() throws -> Int
}
