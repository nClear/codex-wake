import Foundation

protocol ThreadStore: Sendable {
    func loadThreads() throws -> [CodexThread]
    func loadPreview(for thread: CodexThread) throws -> ThreadPreview
    func threadContainsRawText(_ thread: CodexThread, query: String) throws -> Bool
    func wake(thread: CodexThread) throws -> WakeReport
}
