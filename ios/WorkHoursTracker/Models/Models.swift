import Foundation

enum SessionStatus: String, Codable {
    case open, closed, needsReview = "needs_review", deleted
}

enum EventSource: String, Codable {
    case siri, app, web, `import`, automation
}

struct WorkSession: Codable, Identifiable, Equatable {
    let id: String
    var userId: String
    var startUtc: String
    var endUtc: String?
    var startTimezoneId: String
    var endTimezoneId: String?
    var durationSeconds: Int?
    var note: String?
    var status: String
    var source: String
    var needsReview: Bool
    var validationWarnings: [String]
    var createdAt: String?
    var updatedAt: String?
    var deletedAt: String?
    var updatedSeq: Int?

    var start: Date { ISO8601.date(startUtc) ?? Date() }
    var end: Date? { endUtc.flatMap { ISO8601.date($0) } }
    var isOpen: Bool { endUtc == nil && status != "deleted" }

    // The server includes a pre-computed durationSeconds snapshot even for open
    // sessions, so it's frozen at whatever it was when last fetched. Always
    // compute live elapsed time client-side while the session is open instead.
    var liveDurationSeconds: Int {
        if isOpen { return max(0, Int(Date().timeIntervalSince(start))) }
        return durationSeconds ?? 0
    }
}

struct ClockEvent: Codable, Identifiable {
    let id: String
    var type: String
    var timestampUtc: String
    var timezoneId: String
    var localDate: String
    var note: String?
    var source: String
    var deviceId: String?
    var appVersion: String?
    var sessionId: String?
}

struct DailySummary: Codable {
    var date: String
    var totalHuman: String
    var allocatedHuman: String
    var sessionCount: Int
    var openSessions: Int
    var firstClockIn: String?
    var lastClockOut: String?
    var notes: [String]
    var warnings: [String]
    var sessions: [WorkSession]
}

struct DayBreakdown: Codable, Identifiable {
    var date: String
    var seconds: Int
    var human: String
    var id: String { date }
}

struct WeeklySummary: Codable {
    var weekStart: String
    var totalHuman: String
    var sessionCount: Int
    var averagePerDayHuman: String
    var longestDay: DayBreakdown?
    var dailyBreakdown: [DayBreakdown]
    var notes: [String]
    var sessions: [WorkSession]
}

struct AuthResponse: Codable {
    var token: String
    var user: UserProfile
}

struct UserProfile: Codable {
    var id: String
    var email: String
    var displayName: String
    var timezonePreference: String
    var weekStartsOn: Int
}

struct ClockResponse: Codable {
    var status: String
    var session: WorkSession?
    var message: String
}

enum ISO8601 {
    static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let plainFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static func date(_ s: String) -> Date? {
        formatter.date(from: s) ?? plainFormatter.date(from: s)
    }
    static func string(_ d: Date) -> String { plainFormatter.string(from: d) }
}
