import Foundation

enum Format {
    static func duration(_ seconds: Int?) -> String {
        guard let seconds else { return "—" }
        let h = seconds / 3600, m = (seconds % 3600) / 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    /// Live, ticking clock — H:MM:SS, truncated to M:SS while under an hour.
    static func liveClock(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    static func time(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    static func timeRange(_ session: WorkSession) -> String {
        let start = time(session.start)
        if let end = session.end { return "\(start) – \(time(end))" }
        return "\(start) – Now"
    }

    static func weekday(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE"
        return f.string(from: date)
    }

    static func dayNum(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d"
        return f.string(from: date)
    }
}
