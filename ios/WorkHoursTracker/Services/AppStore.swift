import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var isAuthenticated = false
    @Published var profile: UserProfile?
    @Published var openSession: WorkSession?
    @Published var sessions: [WorkSession] = []
    @Published var events: [ClockEvent] = []
    @Published var weekly: WeeklySummary?
    @Published var daily: DailySummary?
    @Published var errorMessage: String?
    @Published var isBusy = false

    // Anchor date used by the calendar for week/day/month navigation.
    @Published var anchorDate = Date()

    func bootstrap() async {
        if UserDefaults.standard.string(forKey: "auth_token") != nil {
            isAuthenticated = true
            await refreshAll()
        }
    }

    func login(email: String, password: String) async {
        isBusy = true; defer { isBusy = false }
        do {
            let auth = try await APIClient.shared.login(email: email, password: password)
            profile = auth.user
            isAuthenticated = true
            await refreshAll()
        } catch { errorMessage = "Login failed. Check your details and that the server is running." }
    }

    func register(email: String, password: String, name: String) async {
        isBusy = true; defer { isBusy = false }
        do {
            let auth = try await APIClient.shared.register(
                email: email, password: password, displayName: name, timezone: TimeZone.current.identifier)
            profile = auth.user
            isAuthenticated = true
            await refreshAll()
        } catch { errorMessage = "Sign up failed. That email may already be registered." }
    }

    func logout() {
        Task { await APIClient.shared.setToken(nil) }
        isAuthenticated = false
        profile = nil
        sessions = []
        openSession = nil
    }

    func clockIn(note: String?) async {
        let result = await ClockService.clockIn(note: note)
        errorMessage = nil
        openSession = result.session
        await refreshAll()
    }

    func clockOut(note: String?) async {
        _ = await ClockService.clockOut(note: note)
        openSession = nil
        await refreshAll()
    }

    func refreshAll() async {
        await refreshOpenSession()
        await refreshWeek()
        await refreshDay()
        await refreshEvents()
    }

    func refreshOpenSession() async {
        openSession = try? await APIClient.shared.clockState()
        LocalStore.cacheOpenSession(openSession)
    }

    func refreshWeek() async {
        let iso = isoDate(anchorDate)
        weekly = try? await APIClient.shared.weeklySummary(weekStart: iso)
        if let start = weekBounds(anchorDate).0, let end = weekBounds(anchorDate).1 {
            sessions = (try? await APIClient.shared.sessions(start: start, end: end)) ?? []
        }
    }

    func refreshDay() async {
        daily = try? await APIClient.shared.dailySummary(date: isoDate(anchorDate))
    }

    func refreshEvents() async {
        let cal = Calendar.current
        let end = Date()
        let start = cal.date(byAdding: .day, value: -30, to: end) ?? end
        events = (try? await APIClient.shared.events(start: start, end: end)) ?? []
    }

    func deleteSession(_ session: WorkSession) async {
        try? await APIClient.shared.deleteSession(id: session.id)
        await refreshAll()
    }

    func updateSession(_ id: String, start: Date, end: Date?, note: String) async {
        var changes: [String: String] = ["startUtc": ISO8601.string(start), "note": note]
        if let end { changes["endUtc"] = ISO8601.string(end) }
        _ = try? await APIClient.shared.updateSession(id: id, changes: changes)
        await refreshAll()
    }

    // MARK: helpers
    func isoDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.string(from: d)
    }

    func weekBounds(_ d: Date) -> (Date?, Date?) {
        var cal = Calendar.current
        cal.firstWeekday = (profile?.weekStartsOn ?? 0) + 1
        guard let interval = cal.dateInterval(of: .weekOfYear, for: d) else { return (nil, nil) }
        return (interval.start, interval.end)
    }
}
