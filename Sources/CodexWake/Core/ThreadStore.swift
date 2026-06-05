import Foundation

protocol ThreadStore: Sendable {
    func loadThreads() throws -> [CodexThread]
    func loadBackups() throws -> [BackupFile]
    func loadBackupTrash() throws -> [BackupFile]
    func loadPreview(for thread: CodexThread) throws -> ThreadPreview
    func threadContainsRawText(_ thread: CodexThread, query: String) throws -> Bool
    func wake(thread: CodexThread) throws -> WakeReport
    func trim(thread: CodexThread, fromLine lineNumber: Int) throws -> TrimReport
    func branch(thread: CodexThread, fromLine lineNumber: Int) throws -> BranchReport
    func move(thread: CodexThread, to project: ProjectSummary) throws -> MoveReport
    func restoreBackup(_ backup: BackupFile) throws
    func moveBackupToTrash(_ backup: BackupFile) throws
    func emptyBackupTrash() throws -> Int
}
