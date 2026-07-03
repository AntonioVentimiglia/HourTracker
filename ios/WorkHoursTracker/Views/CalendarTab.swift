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
                .padding([.horizontal, .top])

                navHeader.padding(.vertical, 12)

                ScrollView {
                    VStack(spacing: 12) {
                        switch mode {
                        case .day: DayView(day: store.anchorDate, onTap: { editing = $0 })
                        case .week: WeekView(onTap: { editing = $0 })
                        case .month: MonthView()
                        }
                    }
                    .padding(.horizontal)
                    Color.clear.frame(height: 140) // clock bar clearance
                }
            }
            .background(Color(.systemGroupedBackground))
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
            Button { shift(-1) } label: { Image(systemName: "chevron.left").font(.headline) }
            Spacer()
            VStack(spacing: 2) {
                Text(headerTitle).font(.headline)
                HStack(spacing: 6) {
                    Text("Billed \(billedLabel)").foregroundStyle(.indigo).fontWeight(.semibold)
                    Text("· Raw \(rawLabel)").foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right").font(.headline) }
        }
        .padding(.horizontal)
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

    var billedLabel: String {
        switch mode {
        case .day: return Format.decimalHours(store.daily?.billedSeconds)
        default: return Format.decimalHours(store.weekly?.billedSeconds)
        }
    }

    var rawLabel: String {
        switch mode {
        case .day: return store.daily?.rawHuman ?? store.daily?.allocatedHuman ?? "0m"
        default: return store.weekly?.rawHuman ?? store.weekly?.totalHuman ?? "0m"
        }
    }

    func shift(_ n: Int) {
        let comp: Calendar.Component = mode == .day ? .day : (mode == .week ? .weekOfYear : .month)
        store.anchorDate = Calendar.current.date(byAdding: comp, value: n, to: store.anchorDate) ?? store.anchorDate
    }
}

// MARK: - Week

struct WeekView: View {
    @EnvironmentObject var store: AppStore
    var onTap: (WorkSession) -> Void

    var days: [Date] {
        let (start, _) = store.weekBounds(store.anchorDate)
        guard let start else { return [] }
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        ForEach(days, id: \.self) { day in
            let cal = Calendar.current
            let sessions = store.sessions.filter { cal.isDate($0.start, inSameDayAs: day) }
            DayRow(day: day, sessions: sessions, blocks: store.blocks(on: day), onTap: onTap)
        }
    }
}

struct DayRow: View {
    var day: Date
    var sessions: [WorkSession]
    var blocks: [BillingBlock]
    var onTap: (WorkSession) -> Void

    var rawSeconds: Int { sessions.reduce(0) { $0 + $1.liveDurationSeconds } }
    var billedSeconds: Int { blocks.count * 900 }

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(Format.weekday(day)).font(.subheadline.weight(.bold))
                Text(Format.dayNum(day)).foregroundStyle(.secondary)
                Spacer()
                if billedSeconds > 0 {
                    Text(Format.decimalHours(billedSeconds))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.indigo)
                    Text("· \(Format.duration(rawSeconds))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            if !blocks.isEmpty { BlockStrip(blocks: blocks) }
            ForEach(sessions) { s in
                SessionRow(session: s).contentShape(Rectangle()).onTapGesture { onTap(s) }
            }
        }
    }
}

// MARK: - Day

struct DayView: View {
    @EnvironmentObject var store: AppStore
    var day: Date
    var onTap: (WorkSession) -> Void

    var sessions: [WorkSession] {
        store.sessions.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
            .sorted { $0.start < $1.start }
    }
    var blocks: [BillingBlock] { store.blocks(on: day) }

    var body: some View {
        BilledVsRawHero(
            billedHuman: Format.duration(blocks.count * 900),
            billedSeconds: blocks.count * 900,
            rawHuman: store.daily?.rawHuman ?? Format.duration(sessions.reduce(0) { $0 + $1.liveDurationSeconds }),
            blockCount: blocks.count
        )

        Card(title: "Billed 15-minute blocks", systemImage: "square.grid.2x2") {
            if blocks.isEmpty {
                Text("No billable time this day.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                BlockStrip(blocks: blocks)
                ForEach(blocks) { b in
                    HStack {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.indigo).font(.caption)
                        Text("\(Format.time(b.start)) – \(Format.time(b.end))").font(.subheadline)
                        Spacer()
                        Text("0.25 hr").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }

        Card(title: "Clock in / out sessions", systemImage: "clock") {
            if sessions.isEmpty {
                Text("No sessions this day. Tap ＋ to add one, or say “clock me in.”")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 12)
            } else {
                ForEach(sessions) { s in
                    SessionRow(session: s).contentShape(Rectangle()).onTapGesture { onTap(s) }
                }
            }
        }
    }
}

// MARK: - Month

struct MonthView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        Card(title: "Daily totals (selected week)", systemImage: "chart.bar") {
            let days = store.weekly?.dailyBreakdown ?? []
            if days.isEmpty {
                Text("No tracked time.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(days) { d in
                    HStack {
                        Text(d.date).font(.subheadline)
                        Spacer()
                        if let billed = store.weekly?.billedByDay?[d.date], billed > 0 {
                            Text(Format.decimalHours(billed)).foregroundStyle(.indigo).fontWeight(.semibold)
                        }
                        Text("· \(d.human)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        Card(title: "Tip", systemImage: "info.circle") {
            Text("Switch to Week or Day for session detail and the individual billed blocks.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Shared pieces

/// A compact horizontal strip of 15-minute billed blocks (each pip = one block).
struct BlockStrip: View {
    var blocks: [BillingBlock]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(blocks) { _ in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.indigo.opacity(0.6))
                    .frame(height: 10)
            }
        }
    }
}

struct SessionRow: View {
    var session: WorkSession
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(session.isOpen ? Color.green : Color.indigo)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(Format.timeRange(session)).font(.subheadline.weight(.semibold))
                    if session.isOpen { Chip(text: "active", color: .green) }
                }
                Text(Format.duration(session.liveDurationSeconds))
                    .font(.caption).foregroundStyle(.secondary)
                if let note = session.note, !note.isEmpty {
                    Text(note).font(.caption).lineLimit(1).foregroundStyle(.secondary)
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
            .font(.caption).foregroundStyle(.tertiary)
    }
}
