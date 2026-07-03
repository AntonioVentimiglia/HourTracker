import SwiftUI

enum CalendarMode: String, CaseIterable { case month = "Month", day = "Day" }

struct CalendarTab: View {
    @EnvironmentObject var store: AppStore
    @State private var mode: CalendarMode = .month
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

                header

                switch mode {
                case .month:
                    MonthGrid(anchor: store.anchorDate) { day in
                        store.anchorDate = day
                        withAnimation { mode = .day }
                    }
                case .day:
                    TwoDayTimeline(anchor: store.anchorDate, onTap: { editing = $0 })
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
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

    var header: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left").font(.headline) }
            Spacer()
            VStack(spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.indigo)
            }
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right").font(.headline) }
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    var title: String {
        let f = DateFormatter()
        f.dateFormat = mode == .month ? "MMMM yyyy" : "EEE, MMM d"
        return f.string(from: store.anchorDate)
    }

    var subtitle: String {
        switch mode {
        case .month:
            let billed = store.billingBlocks.filter {
                Calendar.current.isDate($0.start, equalTo: store.anchorDate, toGranularity: .month)
            }.count * 900
            return "Billed \(Format.decimalHours(billed)) this month"
        case .day:
            let days = [store.anchorDate, TimeMath.add(days: 1, to: store.anchorDate)]
            let billed = days.reduce(0) { $0 + store.blocks(on: $1).count * 900 }
            return "Billed \(Format.decimalHours(billed)) shown"
        }
    }

    func shift(_ n: Int) {
        let comp: Calendar.Component = mode == .month ? .month : .day
        let step = mode == .day ? n * 2 : n
        store.anchorDate = Calendar.current.date(byAdding: comp, value: step, to: store.anchorDate) ?? store.anchorDate
    }
}

// MARK: - Month grid

struct MonthGrid: View {
    @EnvironmentObject var store: AppStore
    var anchor: Date
    var onSelectDay: (Date) -> Void

    var body: some View {
        let weeks = TimeMath.monthWeeks(around: anchor, firstWeekday: (store.profile?.weekStartsOn ?? 0) + 1)
        VStack(spacing: 0) {
            weekdayHeader
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(weeks.indices, id: \.self) { i in
                        WeekRow(days: weeks[i], anchorMonth: anchor, onSelectDay: onSelectDay)
                        Divider()
                    }
                }
                Color.clear.frame(height: 130)
            }
        }
    }

    var weekdayHeader: some View {
        let symbols = TimeMath.weekdaySymbols(firstWeekday: (store.profile?.weekStartsOn ?? 0) + 1)
        return HStack(spacing: 0) {
            ForEach(symbols, id: \.self) { s in
                Text(s).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            Text("Wk").font(.caption2.weight(.bold)).foregroundStyle(.indigo)
                .frame(width: 44)
        }
        .padding(.vertical, 6)
    }
}

struct WeekRow: View {
    @EnvironmentObject var store: AppStore
    var days: [Date]
    var anchorMonth: Date
    var onSelectDay: (Date) -> Void

    var weekBilled: Int {
        days.reduce(0) { $0 + store.blocks(on: $1).count * 900 }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                MonthDayCell(day: day,
                             inMonth: Calendar.current.isDate(day, equalTo: anchorMonth, toGranularity: .month),
                             sessions: store.sessions.filter { Calendar.current.isDate($0.start, inSameDayAs: day) },
                             blocks: store.blocks(on: day))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelectDay(day) }
            }
            // Week total column
            VStack {
                if weekBilled > 0 {
                    Text(Format.decimalHours(weekBilled))
                        .font(.caption2.weight(.bold)).foregroundStyle(.indigo)
                        .minimumScaleFactor(0.6).lineLimit(1)
                }
            }
            .frame(width: 44)
        }
        .frame(minHeight: 78)
    }
}

struct MonthDayCell: View {
    var day: Date
    var inMonth: Bool
    var sessions: [WorkSession]
    var blocks: [BillingBlock]

    // Billed minutes per session = (blocks tagged to that session) * 15.
    var perSessionBilled: [(session: WorkSession, minutes: Int)] {
        let counts = Dictionary(grouping: blocks, by: { $0.sessionId ?? "" }).mapValues { $0.count }
        return sessions.compactMap { s in
            let m = (counts[s.id] ?? 0) * 15
            return m > 0 ? (s, m) : nil
        }
    }

    var dayBilled: Int { blocks.count * 900 }

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(Format.dayNum(day))
                    .font(.footnote.weight(isToday ? .bold : .regular))
                    .foregroundStyle(dayNumberColor)
                    .frame(width: 22, height: 22)
                    .background(isToday ? Color.red : Color.clear, in: Circle())
                Spacer()
            }
            // Per-session banners (rounded/billed length)
            VStack(spacing: 2) {
                ForEach(perSessionBilled.prefix(3), id: \.session.id) { item in
                    Text(Format.duration(item.minutes * 60))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(Palette.raw, in: RoundedRectangle(cornerRadius: 3))
                }
                if perSessionBilled.count > 3 {
                    Text("+\(perSessionBilled.count - 3)")
                        .font(.system(size: 8)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            if dayBilled > 0 {
                Text(Format.decimalHours(dayBilled))
                    .font(.system(size: 8.5, weight: .bold)).foregroundStyle(.indigo)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var isToday: Bool { Calendar.current.isDateInToday(day) }

    var dayNumberColor: Color {
        if isToday { return .white }
        return inMonth ? Color(.label) : Color(.tertiaryLabel)
    }
}

// MARK: - Two-day timeline

struct TwoDayTimeline: View {
    @EnvironmentObject var store: AppStore
    var anchor: Date
    var onTap: (WorkSession) -> Void

    private let hourHeight: CGFloat = 52
    private let gutter: CGFloat = 48
    private var days: [Date] { [anchor, TimeMath.add(days: 1, to: anchor)] }

    private func sessions(on day: Date) -> [WorkSession] {
        store.sessions.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
    }

    /// Window the timeline to the active hours (default 7am–8pm), expanding to
    /// include any earlier/later activity across both days. Avoids a mostly
    /// empty 24-hour scroll and shows the workday immediately.
    private var window: (start: Int, end: Int) {
        var lo = 7, hi = 20
        let cal = Calendar.current
        for day in days {
            for s in sessions(on: day) {
                lo = min(lo, cal.component(.hour, from: s.start))
                let end = s.end ?? Date()
                hi = max(hi, cal.component(.hour, from: end) + 1)
            }
            for b in store.blocks(on: day) {
                lo = min(lo, cal.component(.hour, from: b.start))
                hi = max(hi, cal.component(.hour, from: b.end) + 1)
            }
        }
        return (max(0, lo), min(24, max(hi, lo + 4)))
    }

    private var timelineHeight: CGFloat { CGFloat(window.end - window.start) * hourHeight }

    var body: some View {
        VStack(spacing: 0) {
            dayHeaders
            Divider()
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    hourGutter
                    ForEach(days, id: \.self) { day in
                        DayColumn(day: day,
                                  sessions: sessions(on: day),
                                  blocks: store.blocks(on: day),
                                  hourHeight: hourHeight,
                                  startHour: window.start,
                                  endHour: window.end,
                                  onTap: onTap)
                            .frame(maxWidth: .infinity)
                        Divider()
                    }
                }
                .frame(height: timelineHeight)
                Color.clear.frame(height: 130)
            }
        }
    }

    var dayHeaders: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: gutter)
            ForEach(days, id: \.self) { day in
                let billed = store.blocks(on: day).count * 900
                let raw = store.sessions.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
                    .reduce(0) { $0 + $1.liveDurationSeconds }
                VStack(spacing: 2) {
                    Text(TimeMath.weekdayFull(day))
                        .font(.subheadline.weight(Calendar.current.isDateInToday(day) ? .bold : .semibold))
                        .foregroundStyle(Calendar.current.isDateInToday(day) ? .red : .primary)
                    HStack(spacing: 6) {
                        Text(Format.decimalHours(billed)).foregroundStyle(.indigo).fontWeight(.semibold)
                        Text("· \(Format.duration(raw))").foregroundStyle(.secondary)
                    }
                    .font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 44)
        .padding(.vertical, 8)
    }

    var hourGutter: some View {
        ZStack(alignment: .top) {
            ForEach(window.start..<window.end, id: \.self) { h in
                Text(TimeMath.hourLabel(h))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .frame(width: gutter, alignment: .trailing)
                    .padding(.trailing, 4)
                    .offset(y: CGFloat(h - window.start) * hourHeight - 5)
            }
        }
        .frame(width: gutter, height: timelineHeight, alignment: .top)
    }
}

struct DayColumn: View {
    var day: Date
    var sessions: [WorkSession]
    var blocks: [BillingBlock]
    var hourHeight: CGFloat
    var startHour: Int
    var endHour: Int
    var onTap: (WorkSession) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Hour gridlines
            ForEach(startHour..<endHour, id: \.self) { h in
                Rectangle().fill(Color(.separator).opacity(0.4)).frame(height: 0.5)
                    .offset(y: CGFloat(h - startHour) * hourHeight)
            }
            // Billed 15-min blocks (light, stretched over their time span)
            ForEach(blocks) { b in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Palette.billed)
                    .frame(height: span(b.start, b.end))
                    .padding(.horizontal, 2)
                    .offset(y: yFor(b.start))
            }
            // Raw sessions (solid, same hue) on top
            ForEach(sessions) { s in
                SessionBox(session: s, height: span(s.start, s.end ?? Date()))
                    .offset(y: yFor(s.start))
                    .onTapGesture { onTap(s) }
            }
            // Current-time indicator
            if Calendar.current.isDateInToday(day) {
                NowLine().offset(y: yFor(Date()))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// y-offset for a time, relative to the window's start hour, clamped to day.
    func yFor(_ date: Date) -> CGFloat {
        let cal = Calendar.current
        let windowStart = cal.startOfDay(for: day).addingTimeInterval(Double(startHour) * 3600)
        let secs = date.timeIntervalSince(windowStart)
        return CGFloat(secs) / 3600.0 * hourHeight
    }

    func span(_ start: Date, _ end: Date) -> CGFloat {
        max(6, CGFloat(end.timeIntervalSince(start)) / 3600.0 * hourHeight)
    }
}

struct SessionBox: View {
    var session: WorkSession
    var height: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.8)).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(Format.timeRange(session))
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                if height > 28, let note = session.note, !note.isEmpty {
                    Text(note).font(.system(size: 9)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5).padding(.vertical, 2)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(Palette.raw.opacity(session.isOpen ? 0.75 : 0.9), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.5), lineWidth: 0.5))
        .padding(.trailing, 8)
    }
}

struct NowLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle().fill(.red).frame(width: 7, height: 7)
            Rectangle().fill(.red).frame(height: 1.5)
        }
    }
}

// MARK: - Date helpers

enum TimeMath {
    static func add(days: Int, to date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func monthWeeks(around date: Date, firstWeekday: Int) -> [[Date]] {
        var cal = Calendar.current
        cal.firstWeekday = firstWeekday
        guard let monthInterval = cal.dateInterval(of: .month, for: date) else { return [] }
        let firstOfMonth = monthInterval.start
        let weekday = cal.component(.weekday, from: firstOfMonth)
        let offset = (weekday - firstWeekday + 7) % 7
        let gridStart = cal.date(byAdding: .day, value: -offset, to: firstOfMonth) ?? firstOfMonth
        return (0..<6).map { week in
            (0..<7).compactMap { d in
                cal.date(byAdding: .day, value: week * 7 + d, to: gridStart)
            }
        }
    }

    static func weekdaySymbols(firstWeekday: Int) -> [String] {
        let base = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let start = firstWeekday - 1
        return (0..<7).map { base[($0 + start) % 7] }
    }

    static func weekdayFull(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE d"
        return f.string(from: date)
    }

    static func hourLabel(_ h: Int) -> String {
        if h == 0 { return "12 AM" }
        if h == 12 { return "12 PM" }
        return h < 12 ? "\(h) AM" : "\(h - 12) PM"
    }
}
