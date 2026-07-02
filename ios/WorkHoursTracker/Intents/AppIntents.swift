import AppIntents

/// ClockInIntent — starts a work session. Runs in the background (no app launch),
/// accepts an optional note, and leaves the note parameter unresolved so Siri can
/// ask "What are you working on?" as a robust two-turn flow for arbitrary dictation.
struct ClockInIntent: AppIntent {
    static var title: LocalizedStringResource = "Clock In"
    static var description = IntentDescription("Start tracking your work time.")

    // openAppWhenRun = false lets the action complete while the device is locked.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Note", requestValueDialog: "What are you working on?")
    var note: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await ClockService.clockIn(note: note)
        return .result(dialog: IntentDialog(stringLiteral: result.message))
    }
}

/// ClockOutIntent — ends the current open session with an optional wrap-up note.
struct ClockOutIntent: AppIntent {
    static var title: LocalizedStringResource = "Clock Out"
    static var description = IntentDescription("Stop tracking your work time.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Note")
    var note: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await ClockService.clockOut(note: note)
        return .result(dialog: IntentDialog(stringLiteral: result.message))
    }
}

/// AddWorkNoteIntent — attaches a note to the current session (or standalone).
struct AddWorkNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Work Note"
    static var description = IntentDescription("Add a note to your current work session.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Note", requestValueDialog: "What's the note?")
    var note: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Reuse clockIn's append behavior when clocked in via the server.
        let today = await ClockService.todayHoursSpoken()
        // A dedicated note push:
        let action = QueuedAction(type: "note", note: note,
                                  timestampUtc: ISO8601.string(Date()),
                                  timezoneId: TimeZone.current.identifier,
                                  source: "siri", deviceId: DeviceInfo.id,
                                  appVersion: DeviceInfo.appVersion,
                                  idempotencyKey: UUID().uuidString)
        LocalStore.enqueue(action)
        try? await APIClient.shared.pushQueued(LocalStore.queued())
        _ = today
        return .result(dialog: "Noted: \(note).")
    }
}

/// ShowTodayHoursIntent — Siri reports today's tracked total.
struct ShowTodayHoursIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Today's Hours"
    static var description = IntentDescription("Ask how many hours you've tracked today.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let msg = await ClockService.todayHoursSpoken()
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}

/// ShowWeekHoursIntent — Siri reports this week's tracked total.
struct ShowWeekHoursIntent: AppIntent {
    static var title: LocalizedStringResource = "Show This Week's Hours"
    static var description = IntentDescription("Ask how many hours you've tracked this week.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        let weekStart = f.string(from: Date())
        if let summary = try? await APIClient.shared.weeklySummary(weekStart: weekStart) {
            return .result(dialog: "You have tracked \(summary.totalHuman) this week.")
        }
        return .result(dialog: "I couldn't reach your data right now.")
    }
}
