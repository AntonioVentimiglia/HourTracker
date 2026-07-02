import AppIntents

/// App Shortcuts register spoken phrases with the system at install time.
/// Per Apple's guidance (and the brief §3.2), each phrase includes the app name.
/// Users wanting the bare "clock me in" can add a personal shortcut that runs
/// ClockInIntent — documented on the onboarding screen.
///
/// `\(.applicationName)` expands to the app's name; provide several natural
/// variations per intent so recognition is more forgiving.
struct WorkHoursShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ClockInIntent(),
            phrases: [
                "Clock me in with \(.applicationName)",
                "Start work with \(.applicationName)",
                "Clock in with \(.applicationName)",
                "Begin tracking with \(.applicationName)"
            ],
            shortTitle: "Clock In",
            systemImageName: "play.circle.fill"
        )
        AppShortcut(
            intent: ClockOutIntent(),
            phrases: [
                "Clock me out with \(.applicationName)",
                "Stop work with \(.applicationName)",
                "Clock out with \(.applicationName)",
                "Stop tracking with \(.applicationName)"
            ],
            shortTitle: "Clock Out",
            systemImageName: "stop.circle.fill"
        )
        AppShortcut(
            intent: AddWorkNoteIntent(),
            phrases: [
                "Add a work note with \(.applicationName)",
                "Add note with \(.applicationName)"
            ],
            shortTitle: "Add Note",
            systemImageName: "note.text"
        )
        AppShortcut(
            intent: ShowTodayHoursIntent(),
            phrases: [
                "Show today's hours with \(.applicationName)",
                "How many hours today with \(.applicationName)"
            ],
            shortTitle: "Today's Hours",
            systemImageName: "sun.max.fill"
        )
        AppShortcut(
            intent: ShowWeekHoursIntent(),
            phrases: [
                "Show this week's hours with \(.applicationName)",
                "How many hours this week with \(.applicationName)"
            ],
            shortTitle: "This Week's Hours",
            systemImageName: "calendar"
        )
    }
}
