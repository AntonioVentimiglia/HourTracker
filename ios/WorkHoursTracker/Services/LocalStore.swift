import Foundation

/// Offline-first persistence. Siri actions and manual clock actions are written
/// here first (so they work with no network and while the app is closed), then
/// flushed to the backend when connectivity returns.
///
/// App Intents here compile into the main app target (there's no separate
/// extension), so both Siri and the foreground UI already share the same
/// sandbox — standard UserDefaults is enough. (This used to route through an
/// App Group suite that was never actually registered, which made every
/// read/write to it silently fail at the system level.)
enum LocalStore {
    private static var defaults: UserDefaults { .standard }

    private static let queueKey = "queued_actions"
    private static let openSessionKey = "cached_open_session"

    // MARK: Queue
    static func enqueue(_ action: QueuedAction) {
        var q = queued()
        q.append(action)
        if let data = try? JSONEncoder().encode(q) { defaults.set(data, forKey: queueKey) }
    }

    static func queued() -> [QueuedAction] {
        guard let data = defaults.data(forKey: queueKey),
              let q = try? JSONDecoder().decode([QueuedAction].self, from: data) else { return [] }
        return q
    }

    static func clearQueue() { defaults.removeObject(forKey: queueKey) }

    // MARK: Cached open-session flag (so Siri knows state offline)
    static func cacheOpenSession(_ session: WorkSession?) {
        if let session, let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: openSessionKey)
        } else {
            defaults.removeObject(forKey: openSessionKey)
        }
    }

    static func cachedOpenSession() -> WorkSession? {
        guard let data = defaults.data(forKey: openSessionKey) else { return nil }
        return try? JSONDecoder().decode(WorkSession.self, from: data)
    }
}
