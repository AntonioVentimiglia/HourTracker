import SwiftUI

enum CalendarMode: String, CaseIterable { case day = "Day", week = "Week", month = "Month" }

struct CalendarTab: View {
    @EnvironmentObject var store: AppStore
    @State private var mode: CalendarMode = .week
    @State private var editing: WorkSession?
    @State private var creatingNew = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $mode) {
                    ForEach(CalendarMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                navHeader

                ScrollView {
                    switch mode {
                    case .day: DayView(sessions: daySessions, onTap: { editing = $0 })
                    case .week: WeekView(onTap: { editing = $0 })
                    case .month: MonthView()
                    }
                    Color.clear.frame(height: 140) // clock bar clearance
                }
            }
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creatingNew = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Log out", role: .destructive) { store.logout() }
                    } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(item: $editing) { s in SessionEditor(session: s) }
            .sheet(isPresented: $creatingNew) { SessionEditor(session: nil) }
            .task(id: store.anchorDate) { await store.refreshAll() }
        }
    }

    var navHeader: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            VStack {
                Text(headerTitle).font(.headline)
                Text(totalLabel).font(.subheadline).foregroundStyle(.indigo)
            }
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal)
    }

    var daySessions: [WorkSession] {
        let cal = Calendar.current
        return store.sessions.filter { cal.isDate($0.start, inSameDayAs: store.anchorDate) }
    }

    var headerTitle: String {
        let f = DateFormatter()
        switch mode {
        case .day: f.dateFormat = "EEEE, MMM d"
        case .week: f.dateFormat = "MMM d"
        case .month: f.dateFormat = "MMMM yyyy"
        }
        return f.string(from: store.anchorDate)
    }

    var totalLabel: String {
        switch mode {
        case .day: return "Today: \(store.daily?.allocatedHuman ?? "0m")"
        case .week: return "Week: \(store.weekly?.totalHuman ?? "0m")"
        case .month: return "Month total"
        }
    }

    func shift(_ n: Int) {
        let comp: Calendar.Component = mode == .day ? .day : (mode == .week ? .weekOfYear : .month)
        store.anchorDate = Calendar.current.date(byAdding: comp, value: n, to: store.anchorDate) ?? store.anchorDate
    }
}

struct WeekView: View {
    @EnvironmentObject var store: AppStore
    var onTap: (WorkSession) -> Void

    var days: [Date] {
        let (start, _) = store.weekBounds(store.anchorDate)
        guard let start else { return [] }
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(days, id: \.self) { day in
                let cal = Calendar.current
                let sessions = store.sessions.filter { cal.isDate($0.start, inSameDayAs: day) }
                DayRow(day: day, sessions: sessions, onTap: onTap)
            }
        }
        .padding(.horizontal)
    }
}

struct DayRow: View {
    var day: Date
    var sessions: [WorkSession]
    var onTap: (WorkSession) -> Void

    var total: Int { sessions.reduce(0) { $0 + $1.liveDurationSeconds } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Format.weekday(day)).font(.subheadline.bold())
                Text(Format.dayNum(day)).foregroundStyle(.secondary)
                Spacer()
                if total > 0 { Text(Format.duration(total)).font(.subheadline).foregroundStyle(.indigo) }
            }
            ForEach(sessions) { s in SessionBlock(session: s).onTapGesture { onTap(s) } }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct DayView: View {
    var sessions: [WorkSession]
    var onTap: (WorkSession) -> Void
    var body: some View {
        VStack(spacing: 8) {
            if sessions.isEmpty {
                Text("No sessions this day. Tap + to add one, or say “clock me in.”")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            }
            ForEach(sessions) { s in SessionBlock(session: s).onTapGesture { onTap(s) } }
        }
        .padding()
    }
}

struct MonthView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily totals")
                .font(.headline).padding(.horizontal)
            ForEach(store.weekly?.dailyBreakdown ?? []) { d in
                HStack {
                    Text(d.date).font(.subheadline)
                    Spacer()
                    Text(d.human).foregroundStyle(.indigo)
                }
                .padding(.horizontal)
            }
            Text("Switch to Week for full session detail.")
                .font(.caption).foregroundStyle(.secondary).padding()
        }
    }
}

struct SessionBlock: View {
    var session: WorkSession
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(session.isOpen ? Color.green : Color.indigo)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(Format.timeRange(session)).font(.subheadline.bold())
                    if session.isOpen {
                        Text("ACTIVE").font(.caption2.bold()).foregroundStyle(.green)
                    }
                }
                Text(Format.duration(session.liveDurationSeconds))
                    .font(.caption).foregroundStyle(.secondary)
                if let note = session.note, !note.isEmpty {
                    Text(note).font(.caption).lineLimit(1)
                }
                if !session.validationWarnings.isEmpty {
                    Label(session.validationWarnings.joined(separator: ", "),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer()
            SourceIcon(source: session.source)
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SourceIcon: View {
    var source: String
    var body: some View {
        Image(systemName: source == "siri" ? "mic.fill" : source == "web" ? "desktopcomputer" : "iphone")
            .font(.caption).foregroundStyle(.secondary)
    }
}
