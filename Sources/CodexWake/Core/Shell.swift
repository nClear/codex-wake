import Foundation

struct Shell {
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            let message = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw WakeError.commandFailed(message)
        }

        return String(data: outputData, encoding: .utf8) ?? ""
    }
}

enum WakeError: LocalizedError {
    case commandFailed(String)
    case missingCodexHome(URL)
    case missingStateDatabase(URL)
    case invalidJSON(String)
    case missingThreadFile(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        case .missingCodexHome(let url):
            return "Codex home not found: \(url.path)"
        case .missingStateDatabase(let url):
            return "Codex state database not found: \(url.path)"
        case .invalidJSON(let message):
            return "Invalid JSON: \(message)"
        case .missingThreadFile(let path):
            return "Thread file not found: \(path)"
        }
    }
}
