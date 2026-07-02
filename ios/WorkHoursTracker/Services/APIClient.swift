import Foundation

/// Talks to the shared backend. All timestamps are UTC; the timezone identifier
/// travels with each write so the server can bucket days correctly.
actor APIClient {
    static let shared = APIClient()

    /// Point this at your running backend. For the iOS Simulator on a Mac,
    /// `http://localhost:4000` reaches a server running on the same machine.
    /// For a physical device, use your Mac's LAN IP (e.g. http://192.168.1.20:4000).
    var baseURL = URL(string: "http://localhost:4000")!

    private var token: String? {
        get { UserDefaults.standard.string(forKey: "auth_token") }
    }

    func setToken(_ t: String?) {
        UserDefaults.standard.set(t, forKey: "auth_token")
    }

    private func request(_ path: String, method: String = "GET", body: Encodable? = nil, authed: Bool = true) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authed, let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus(String(data: data, encoding: .utf8) ?? "unknown")
        }
        return data
    }

    // MARK: Auth
    func login(email: String, password: String) async throws -> AuthResponse {
        let data = try await request("/auth/login", method: "POST",
                                     body: ["email": email, "password": password], authed: false)
        let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
        setToken(auth.token)
        return auth
    }

    func register(email: String, password: String, displayName: String, timezone: String) async throws -> AuthResponse {
        let data = try await request("/auth/register", method: "POST",
            body: ["email": email, "password": password, "displayName": displayName, "timezonePreference": timezone], authed: false)
        let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
        setToken(auth.token)
        return auth
    }

    // MARK: Clock
    struct ClockBody: Encodable {
        var timestampUtc: String
        var timezoneId: String
        var note: String?
        var source: String
        var deviceId: String?
        var appVersion: String?
        var idempotencyKey: String
    }

    func clockIn(note: String?) async throws -> ClockResponse {
        try await clock(path: "/clock/in", note: note)
    }
    func clockOut(note: String?) async throws -> ClockResponse {
        try await clock(path: "/clock/out", note: note)
    }

    private func clock(path: String, note: String?) async throws -> ClockResponse {
        let body = ClockBody(timestampUtc: ISO8601.string(Date()),
                             timezoneId: TimeZone.current.identifier,
                             note: note, source: "app",
                             deviceId: DeviceInfo.id, appVersion: DeviceInfo.appVersion,
                             idempotencyKey: UUID().uuidString)
        let data = try await request(path, method: "POST", body: body)
        return try JSONDecoder().decode(ClockResponse.self, from: data)
    }

    // MARK: Reads
    func clockState() async throws -> WorkSession? {
        struct R: Codable { var clockedIn: Bool; var session: WorkSession? }
        let data = try await request("/clock/state")
        return try JSONDecoder().decode(R.self, from: data).session
    }

    func sessions(start: Date, end: Date) async throws -> [WorkSession] {
        struct R: Codable { var sessions: [WorkSession] }
        let path = "/sessions?start=\(ISO8601.string(start))&end=\(ISO8601.string(end))"
        let data = try await request(path)
        return try JSONDecoder().decode(R.self, from: data).sessions
    }

    func events(start: Date, end: Date) async throws -> [ClockEvent] {
        struct R: Codable { var events: [ClockEvent] }
        let path = "/events?start=\(ISO8601.string(start))&end=\(ISO8601.string(end))"
        let data = try await request(path)
        return try JSONDecoder().decode(R.self, from: data).events
    }

    func dailySummary(date: String) async throws -> DailySummary {
        let data = try await request("/summaries/daily?date=\(date)")
        return try JSONDecoder().decode(DailySummary.self, from: data)
    }

    func weeklySummary(weekStart: String) async throws -> WeeklySummary {
        let data = try await request("/summaries/weekly?weekStart=\(weekStart)")
        return try JSONDecoder().decode(WeeklySummary.self, from: data)
    }

    struct UpdateBody: Encodable {
        var changes: [String: String]
        var source: String
    }

    func updateSession(id: String, changes: [String: String]) async throws -> WorkSession {
        struct R: Codable { var session: WorkSession }
        let data = try await request("/sessions/\(id)", method: "PATCH",
                                     body: UpdateBody(changes: changes, source: "app"))
        return try JSONDecoder().decode(R.self, from: data).session
    }

    func deleteSession(id: String) async throws {
        _ = try await request("/sessions/\(id)", method: "DELETE")
    }

    struct CreateBody: Encodable {
        var startUtc: String
        var endUtc: String?
        var timezoneId: String
        var note: String?
        var source: String
    }

    func createSession(startUtc: String, endUtc: String?, note: String?) async throws -> WorkSession {
        struct R: Codable { var session: WorkSession }
        let body = CreateBody(startUtc: startUtc, endUtc: endUtc,
                              timezoneId: TimeZone.current.identifier, note: note, source: "app")
        let data = try await request("/sessions", method: "POST", body: body)
        return try JSONDecoder().decode(R.self, from: data).session
    }

    // MARK: Offline sync push
    func pushQueued(_ actions: [QueuedAction]) async throws {
        guard !actions.isEmpty else { return }
        _ = try await request("/sync/push", method: "POST", body: ["actions": actions])
    }
}

enum APIError: Error { case badStatus(String) }

enum DeviceInfo {
    static var id: String {
        if let s = UserDefaults.standard.string(forKey: "device_id") { return s }
        let s = UUID().uuidString
        UserDefaults.standard.set(s, forKey: "device_id")
        return s
    }
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

/// A clock action captured while offline, replayed with an idempotency key.
struct QueuedAction: Codable {
    var type: String          // clock_in | clock_out | note
    var note: String?
    var timestampUtc: String
    var timezoneId: String
    var source: String
    var deviceId: String?
    var appVersion: String?
    var idempotencyKey: String
}

/// Type-erasing wrapper so we can send heterogeneous JSON bodies.
struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFunc = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
