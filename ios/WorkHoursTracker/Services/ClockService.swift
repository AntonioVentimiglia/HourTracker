import Foundation

/// The single place clock-in / clock-out / note logic lives, so the SwiftUI UI
/// and the Siri App Intents behave identically. Offline-first: it updates local
/// state immediately and returns a spoken-friendly confirmation, queuing the
/// action for sync. This lets Siri actions run in the background without opening
/// the app UI, even when the device has no network.
struct ClockService {

    struct Result {
        let message: String
        let session: WorkSession?
    }

    static func clockIn(note: String?) async -> Result {
        // Duplicate clock-in guard using the last known open-session state.
        if let open = LocalStore.cachedOpenSession(), open.isOpen {
            let time = LocalTime.spoken(open.startUtc, zone: open.startTimezoneId)
            return Result(message: "You are already clocked in since \(time).", session: open)
        }

        let now = Date()
        let action = QueuedAction(type: "clock_in", note: note,
                                  timestampUtc: ISO8601.string(now),
                                  timezoneId: TimeZone.current.identifier,
                                  source: "siri", deviceId: DeviceInfo.id,
                                  appVersion: DeviceInfo.appVersion,
                                  idempotencyKey: UUID().uuidString)
        LocalStore.enqueue(action)

        // Optimistic local open session so the UI + Siri agree immediately.
        let optimistic = WorkSession(
            id: "local-\(action.idempotencyKey)", userId: "", startUtc: action.timestampUtc,
            endUtc: nil, startTimezoneId: action.timezoneId, endTimezoneId: nil,
            durationSeconds: nil, note: note, status: "open", source: "siri",
            needsReview: false, validationWarnings: [], createdAt: action.timestampUtc,
            updatedAt: action.timestampUtc, deletedAt: nil, updatedSeq: nil)
        LocalStore.cacheOpenSession(optimistic)

        // Best-effort immediate sync; failure just leaves it queued.
        do {
            try await APIClient.shared.pushQueued(LocalStore.queued())
        } catch {
            print("[ClockService] pushQueued failed: \(error)")
        }
        await refreshFromServer()

        let time = LocalTime.spoken(action.timestampUtc, zone: action.timezoneId)
        let suffix = note.map { " for \($0)" } ?? ""
        return Result(message: "Clocked in at \(time)\(suffix).", session: LocalStore.cachedOpenSession())
    }

    static func clockOut(note: String?) async -> Result {
        guard let open = LocalStore.cachedOpenSession(), open.isOpen else {
            // Still queue it so the server can record the anomaly if it disagrees.
            let action = QueuedAction(type: "clock_out", note: note,
                                      timestampUtc: ISO8601.string(Date()),
                                      timezoneId: TimeZone.current.identifier,
                                      source: "siri", deviceId: DeviceInfo.id,
                                      appVersion: DeviceInfo.appVersion,
                                      idempotencyKey: UUID().uuidString)
            LocalStore.enqueue(action)
            try? await APIClient.shared.pushQueued(LocalStore.queued())
            return Result(message: "You are not currently clocked in.", session: nil)
        }

        let now = Date()
        let action = QueuedAction(type: "clock_out", note: note,
                                  timestampUtc: ISO8601.string(now),
                                  timezoneId: TimeZone.current.identifier,
                                  source: "siri", deviceId: DeviceInfo.id,
                                  appVersion: DeviceInfo.appVersion,
                                  idempotencyKey: UUID().uuidString)
        LocalStore.enqueue(action)

        let seconds = Int(now.timeIntervalSince(open.start))
        LocalStore.cacheOpenSession(nil)
        try? await APIClient.shared.pushQueued(LocalStore.queued())
        await refreshFromServer()

        return Result(message: "Clocked out. You worked \(LocalTime.spokenDuration(seconds)).", session: nil)
    }

    /// Standalone note push, shared by AddWorkNoteIntent and the clock-in/out
    /// follow-up prompts. Attaches to the open session server-side if there is one.
    static func addNote(_ note: String) async {
        let action = QueuedAction(type: "note", note: note,
                                  timestampUtc: ISO8601.string(Date()),
                                  timezoneId: TimeZone.current.identifier,
                                  source: "siri", deviceId: DeviceInfo.id,
                                  appVersion: DeviceInfo.appVersion,
                                  idempotencyKey: UUID().uuidString)
        LocalStore.enqueue(action)
        try? await APIClient.shared.pushQueued(LocalStore.queued())
    }

    static func todayHoursSpoken() async -> String {
        let today = LocalTime.today()
        if let summary = try? await APIClient.shared.dailySummary(date: today) {
            return "You have tracked \(summary.allocatedHuman) today."
        }
        // Offline fallback: report the open session so far.
        if let open = LocalStore.cachedOpenSession(), open.isOpen {
            let seconds = Int(Date().timeIntervalSince(open.start))
            return "Your current session is \(LocalTime.spokenDuration(seconds)) so far."
        }
        return "I couldn't reach your data right now."
    }

    /// Reconcile local cache with the server's canonical open-session state.
    static func refreshFromServer() async {
        do {
            let server = try await APIClient.shared.clockState()
            if let server {
                LocalStore.cacheOpenSession(server)
                LocalStore.clearQueue()
            }
        } catch {
            print("[ClockService] refreshFromServer failed: \(error)")
        }
    }
}

enum LocalTime {
    static func spoken(_ utc: String, zone: String) -> String {
        guard let date = ISO8601.date(utc) else { return "" }
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: zone)
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
    static func spokenDuration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) \(h == 1 ? "hour" : "hours")") }
        if m > 0 { parts.append("\(m) \(m == 1 ? "minute" : "minutes")") }
        return parts.isEmpty ? "less than a minute" : parts.joined(separator: " and ")
    }
    static func today() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.string(from: Date())
    }
}
