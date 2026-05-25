import Foundation

enum WakeDates {
    static let sqliteJSONDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    static func dateFromSeconds(_ seconds: Int64?) -> Date? {
        guard let seconds else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    static func dateFromMilliseconds(_ milliseconds: Int64?) -> Date? {
        guard let milliseconds else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000.0)
    }

    static func parseISO(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let date = isoWithFraction.date(from: string) { return date }
        if let date = isoNoFraction.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }

    static func isoNowForJSONL() -> String {
        let now = Date()
        let fraction = now.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)
        let milliseconds = Int((fraction * 1000).rounded(.down))
        return isoBase.string(from: now).replacingOccurrences(of: "Z", with: String(format: ".%03dZ", milliseconds))
    }

    static func isoNowForIndex() -> String {
        let now = Date()
        let micros = Int(now.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) * 1_000_000)
        return isoBase.string(from: now).replacingOccurrences(of: "Z", with: String(format: ".%06dZ", micros))
    }

    static func display(_ date: Date?) -> String {
        guard let date else { return "-" }
        return displayFormatter.string(from: date)
    }

    private static let isoBase: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
