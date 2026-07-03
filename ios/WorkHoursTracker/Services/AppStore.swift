import Combine
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
    @Published var billingBlocks: [BillingBlock] = []
    @Published var errorMessage: String?
    @Published var isBusy = false

    // Anchor date used by the calendar for week/day/month navigation.
    @Published var anchorDate = Date()

    // refreshAll() can be triggered from several places in close succession
    // (bootstrap, each tab's own .task, returning to foreground). Without
    // this, a slow refresh kicked off before a clock-in can finish after it
    // and overwrite fresh state with stale data — cancel any prior run first.
    private var refreshTask: Task<Void, Never>?

    private var sessionExpiredObserver: NSObjectProtocol?

    private init() {
        sessionExpiredObserver = NotificationCenter.default.addObserver(
            forName: .sessionExpired, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleSessionExpired() }
        }
    }

    private func handleSessionExpired() {
        guard isAuthenticated else { return }
        logout()
        errorMessage = "Your session expired. Please log in again."
    }

    func bootstrap() async {
        if UserDefaults.standard.string(forKey: "auth_token") != nil {
            isAuthenticated = true
            do {
                profile = try await APIClient.shared.me()
            } catch {
                print("[AppStore] bootstrap profile fetch failed: \(error)")
            }
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
        billingBlocks = []
        daily = nil
        weekly = nil
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
        refreshTask?.cancel()
        let task = Task {
            await refreshOpenSession()
            await refreshWeek()
            await refreshDay()
            await refreshEvents()
            await refreshBillingBlocks()
        }
        refreshTask = task
        await task.value
    }

    func refreshOpenSession() async {
        do {
            let session = try await APIClient.shared.clockState()
            openSession = session
            LocalStore.cacheOpenSession(session)
        } catch {
            guard !isCancellation(error) else { return }
            print("[AppStore] refreshOpenSession failed: \(error)")
            errorMessage = "Couldn't refresh your clock status. Check your connection and that the server is running."
        }
    }

    func refreshWeek() async {
        do {
            let iso = isoDate(anchorDate)
            weekly = try await APIClient.shared.weeklySummary(weekStart: iso)
            // Fetch a month-wide window (± a week of slack) so the month grid and
            // the two-day timeline both have their sessions on hand, not just the
            // current week.
            let cal = Calendar.current
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: anchorDate)) ?? anchorDate
            let start = cal.date(byAdding: .day, value: -7, to: monthStart) ?? monthStart
            let end = cal.date(byAdding: .day, value: 7, to: cal.date(byAdding: .month, value: 1, to: monthStart) ?? anchorDate) ?? anchorDate
            sessions = try await APIClient.shared.sessions(start: start, end: end)
        } catch {
            guard !isCancellation(error) else { return }
            print("[AppStore] refreshWeek failed: \(error)")
            errorMessage = "Couldn't refresh this week's data. Check your connection and that the server is running."
        }
    }

    func refreshDay() async {
        do {
            daily = try await APIClient.shared.dailySummary(date: isoDate(anchorDate))
        } catch {
            guard !isCancellation(error) else { return }
            print("[AppStore] refreshDay failed: \(error)")
            errorMessage = "Couldn't refresh today's data. Check your connection and that the server is running."
        }
    }

    func refreshEvents() async {
        do {
            let cal = Calendar.current
            let end = Date()
            let start = cal.date(byAdding: .day, value: -30, to: end) ?? end
            events = try await APIClient.shared.events(start: start, end: end)
        } catch {
            guard !isCancellation(error) else { return }
            print("[AppStore] refreshEvents failed: \(error)")
            errorMessage = "Couldn't refresh recent events. Check your connection and that the server is running."
        }
    }

    func refreshBillingBlocks() async {
        do {
            // Blocks for the month around the anchor date, so day/week/month
            // calendar views all have their blocks on hand.
            let cal = Calendar.current
            let anchor = cal.date(from: cal.dateComponents([.year, .month], from: anchorDate)) ?? anchorDate
            let start = cal.date(byAdding: .month, value: -1, to: anchor) ?? anchor
            let end = cal.date(byAdding: .month, value: 2, to: anchor) ?? anchorDate
            billingBlocks = try await APIClient.shared.billingBlocks(start: start, end: end).blocks
        } catch {
            guard !isCancellation(error) else { return }
            print("[AppStore] refreshBillingBlocks failed: \(error)")
        }
    }

    /// Billing blocks whose start falls on the given calendar day (local zone).
    func blocks(on day: Date) -> [BillingBlock] {
        let cal = Calendar.current
        return billingBlocks.filter { cal.isDate($0.start, inSameDayAs: day) }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    func deleteSession(_ session: WorkSession) async {
        do {
            try await APIClient.shared.deleteSession(id: session.id)
        } catch {
            print("[AppStore] deleteSession failed: \(error)")
            errorMessage = "Couldn't delete that session. Check your connection and that the server is running."
        }
        await refreshAll()
    }

    func updateSession(_ id: String, start: Date, end: Date?, note: String, color: String?) async {
        var changes: [String: String] = ["startUtc": ISO8601.string(start), "note": note]
        if let end { changes["endUtc"] = ISO8601.string(end) }
        // Empty string clears the color server-side (back to default indigo).
        changes["color"] = color ?? ""
        do {
            _ = try await APIClient.shared.updateSession(id: id, changes: changes)
        } catch {
            print("[AppStore] updateSession failed: \(error)")
            errorMessage = "Couldn't save that edit. Check your connection and that the server is running."
        }
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
