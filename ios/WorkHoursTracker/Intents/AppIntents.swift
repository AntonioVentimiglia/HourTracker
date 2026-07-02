import AppIntents

/// Common decline phrases so a spoken/typed "no" doesn't get saved as literal
/// note text — treated the same as staying silent or dismissing the prompt.
private func isDecline(_ text: String) -> Bool {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return ["no", "nope", "no thanks", "nah", "not now", "nevermind", "never mind", "skip", "none", "no note"]
        .contains(normalized)
}

/// Runs an ignorable follow-up value request. Any failure (decline, dismissal,
/// timeout, the whole interaction being swiped away) is swallowed here and
/// reported as "no value" — callers must not treat that as an error.
private func askOptionalNote(_ resolve: () async throws -> String?) async -> String? {
    guard let response = try? await resolve(), !response.isEmpty, !isDecline(response) else { return nil }
    return response
}

/// ClockInIntent — starts a work session. Runs in the background (no app launch).
/// The clock-in is written to the server before any follow-up runs, so a
/// declined, ignored, or dismissed note prompt can never undo or fail it —
/// worst case the user just gets no note attached, and can add one later
/// with "Add a work note".
struct ClockInIntent: AppIntent {
    static var title: LocalizedStringResource = "Clock In"
    static var description = IntentDescription("Start tracking your work time.")

    // openAppWhenRun = false lets the action complete while the device is locked.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Note")
    var note: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await ClockService.clockIn(note: note)

        guard note == nil else {
            return .result(dialog: IntentDialog(stringLiteral: result.message))
        }

        if let addition = await askOptionalNote({
            try await $note.requestValue(IntentDialog(stringLiteral: "\(result.message) Would you like to add a note?"))
        }) {
            await ClockService.addNote(addition)
            return .result(dialog: IntentDialog(stringLiteral: "Noted: \(addition)."))
        }
        return .result(dialog: IntentDialog(stringLiteral: result.message))
    }
}

/// ClockOutIntent — ends the current open session. Same ignorable-follow-up
/// guarantee as ClockInIntent: the clock-out always happens (with whatever
/// note we already have) even if the extra prompt is declined or dismissed.
struct ClockOutIntent: AppIntent {
    static var title: LocalizedStringResource = "Clock Out"
    static var description = IntentDescription("Stop tracking your work time.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Note")
    var note: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var finalNote = note
        if finalNote == nil {
            let hasExistingNote = LocalStore.cachedOpenSession()?.note?.isEmpty == false
            let prompt = hasExistingNote
                ? "Any additional notes to add?"
                : "No note added, what did you work on?"
            finalNote = await askOptionalNote({ try await $note.requestValue(IntentDialog(stringLiteral: prompt)) })
        }
        let result = await ClockService.clockOut(note: finalNote)
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
        await ClockService.addNote(note)
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
