import SwiftUI

enum CalendarMode: String, CaseIterable { case month = "Month", day = "Day" }

struct CalendarTab: View {
    @EnvironmentObject var store: AppStore
    @State private var mode: CalendarMode = .month
    @State private var editing: WorkSession?
    @State private var creatingNew = false
    // Whether the "chosen" day is the second (right) of the two shown days.
    // The pair is always [anchorDate, anchorDate+1].
    @State private var chosenIsSecondDay = false
    // Collapse the day view from two days down to just the chosen day.
    @State private var singleDay = false

    private var anchor: Date { store.anchorDate }
    private var chosenDay: Date { (chosenIsSecondDay && !singleDay) ? TimeMath.add(days: 1, to: anchor) : anchor }
    private var daysShown: [Date] { singleDay ? [chosenDay] : [anchor, TimeMath.add(days: 1, to: anchor)] }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $mode) {
                    ForEach(CalendarMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                switch mode {
                case .month:
                    monthHeader
                    MonthGrid(anchor: anchor) { day in
                        store.anchorDate = day
                        chosenIsSecondDay = false
                        withAnimation { mode = .day }
                    }
                case .day:
                    WeekStrip(week: TimeMath.weekDays(containing: chosenDay,
                                                      firstWeekday: (store.profile?.weekStartsOn ?? 0) + 1),
                              pairStart: singleDay ? chosenDay : anchor,
                              pairCount: singleDay ? 1 : 2,
                              chosen: chosenDay,
                              onTapDay: selectDay,
                              onShiftWeek: { store.anchorDate = TimeMath.add(days: $0 * 7, to: anchor) })
                    TwoDayTimeline(days: daysShown, chosen: chosenDay, onTap: { editing = $0 })
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if mode == .day {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation { singleDay.toggle() }
                        } label: {
                            // Icon shows the layout you'll switch TO.
                            Image(systemName: singleDay ? "rectangle.split.2x1" : "rectangle.portrait")
                        }
                        .accessibilityLabel(singleDay ? "Show two days" : "Show one day")
                    }
                }
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
            .sheet(isPresented: $creatingNew) {
                SessionEditor(session: nil, defaultDate: mode == .day ? chosenDay : nil)
            }
            .task(id: store.anchorDate) { await store.refreshAll() }
        }
    }

    /// Tap in the week strip: choose a shown day (keep pair), or re-anchor to a
    /// new [tapped, tapped+1] pair when tapping a day outside the current two.
    func selectDay(_ day: Date) {
        let cal = Calendar.current
        if singleDay {
            store.anchorDate = cal.startOfDay(for: day)
            chosenIsSecondDay = false
        } else if cal.isDate(day, inSameDayAs: anchor) {
            chosenIsSecondDay = false
        } else if cal.isDate(day, inSameDayAs: TimeMath.add(days: 1, to: anchor)) {
            chosenIsSecondDay = true
        } else {
            store.anchorDate = cal.startOfDay(for: day)
            chosenIsSecondDay = false
        }
    }

    var monthHeader: some View {
        HStack {
            Button { store.anchorDate = TimeMath.add(months: -1, to: anchor) } label: {
                Image(systemName: "chevron.left").font(.headline)
            }
            Spacer()
            VStack(spacing: 2) {
                Text(anchor.formatted(.dateTime.month(.wide).year())).font(.headline)
                let billed = store.billingBlocks.filter {
                    Calendar.current.isDate($0.start, equalTo: anchor, toGranularity: .month)
                }.count * 900
                Text("Billed \(Format.decimalHours(billed)) this month")
                    .font(.caption).foregroundStyle(.indigo)
            }
            Spacer()
            Button { store.anchorDate = TimeMath.add(months: 1, to: anchor) } label: {
                Image(systemName: "chevron.right").font(.headline)
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
    }
}

// MARK: - Week strip (day-view top bar)

struct WeekStrip: View {
    @EnvironmentObject var store: AppStore
    var week: [Date]            // 7 days
    var pairStart: Date         // left day of the shown pair
    var pairCount: Int = 2      // how many days are shown (1 or 2)
    var chosen: Date
    var onTapDay: (Date) -> Void
    var onShiftWeek: (Int) -> Void

    private var pairIndex: Int? {
        week.firstIndex { Calendar.current.isDate($0, inSameDayAs: pairStart) }
    }

    var body: some View {
        HStack(spacing: 4) {
            Button { onShiftWeek(-1) } label: { Image(systemName: "chevron.left") }
            GeometryReader { geo in
                let cellW = geo.size.width / 7
                ZStack(alignment: .leading) {
                    // Shaded oval spanning the shown day(s).
                    if let i = pairIndex {
                        let width = cellW * CGFloat(min(pairCount, 7 - i))
                        Capsule().fill(Color.indigo.opacity(0.15))
                            .frame(width: width - 4, height: 52)
                            .offset(x: cellW * CGFloat(i) + 2)
                    }
                    HStack(spacing: 0) {
                        ForEach(week, id: \.self) { day in
                            DayPip(day: day, isChosen: Calendar.current.isDate(day, inSameDayAs: chosen))
                                .frame(width: cellW)
                                .contentShape(Rectangle())
                                .onTapGesture { onTapDay(day) }
                        }
                    }
                }
            }
            .frame(height: 56)
            Button { onShiftWeek(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
    }
}

struct DayPip: View {
    @EnvironmentObject var store: AppStore
    var day: Date
    var isChosen: Bool

    var body: some View {
        let hasActivity = !store.blocks(on: day).isEmpty
        VStack(spacing: 3) {
            Text(TimeMath.weekdayLetter(day))
                .font(.caption2).foregroundStyle(.secondary)
            Text(Format.dayNum(day))
                .font(.subheadline.weight(isChosen ? .bold : .regular))
                .foregroundStyle(isChosen ? .white : Color(.label))
                .frame(width: 30, height: 30)
                .background(isChosen ? Color.indigo : Color.clear, in: Circle())
            Circle().fill(hasActivity ? Color.indigo : .clear).frame(width: 4, height: 4)
        }
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
                        .background(ActivityPalette.color(item.session.color), in: RoundedRectangle(cornerRadius: 3))
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
    var days: [Date]
    var chosen: Date
    var onTap: (WorkSession) -> Void

    // Pinch to zoom the hour spacing. baseHourHeight persists the zoom; the
    // live pinch multiplies it, clamped to a readable range.
    @State private var baseHourHeight: CGFloat = 52
    @GestureState private var pinch: CGFloat = 1
    private var hourHeight: CGFloat { min(150, max(30, baseHourHeight * pinch)) }

    private let gutter: CGFloat = 48

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
                            .background(days.count > 1 && Calendar.current.isDate(day, inSameDayAs: chosen)
                                        ? Color.indigo.opacity(0.04) : .clear)
                        Divider()
                    }
                }
                .frame(height: timelineHeight)
                Color.clear.frame(height: 130)
            }
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { baseHourHeight = min(150, max(30, baseHourHeight * $0.magnification)) }
            )
        }
    }

    var dayHeaders: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: gutter)
            ForEach(days, id: \.self) { day in
                let billed = store.blocks(on: day).count * 900
                let raw = store.sessions.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
                    .reduce(0) { $0 + $1.liveDurationSeconds }
                let isChosen = Calendar.current.isDate(day, inSameDayAs: chosen)
                VStack(spacing: 2) {
                    Text(TimeMath.weekdayFull(day))
                        .font(.subheadline.weight(isChosen ? .bold : .semibold))
                        .foregroundStyle(Calendar.current.isDateInToday(day) ? .red : (isChosen ? .indigo : .primary))
                    HStack(spacing: 6) {
                        Text(Format.decimalHours(billed)).foregroundStyle(.indigo).fontWeight(.semibold)
                        Text("· \(Format.duration(raw))").foregroundStyle(.secondary)
                    }
                    .font(isChosen ? .caption.weight(.semibold) : .caption2)
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottom) {
                    if isChosen { Capsule().fill(Color.indigo).frame(width: 28, height: 2).offset(y: 4) }
                }
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

    /// Color of the session that produced a given billed block, so a block is
    /// tinted to match the raw activity that caused it.
    private var colorForSession: [String: String?] {
        Dictionary(sessions.map { ($0.id, $0.color) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Hour gridlines
            ForEach(startHour..<endHour, id: \.self) { h in
                Rectangle().fill(Color(.separator).opacity(0.4)).frame(height: 0.5)
                    .offset(y: CGFloat(h - startHour) * hourHeight)
            }
            // Billed 15-min blocks: light bordered containers, each stretched
            // over the 15 minutes it owns, tiled so every block is a distinct
            // outlined cell even under a long session. Tinted to the raw
            // activity's color.
            ForEach(blocks) { b in
                let hue = ActivityPalette.color(colorForSession[b.sessionId ?? ""] ?? nil)
                RoundedRectangle(cornerRadius: 4)
                    .fill(hue.opacity(0.22))
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(hue.opacity(0.45), lineWidth: 1))
                    .frame(height: span(b.start, b.end) - 1)
                    .padding(.horizontal, 2)
                    .offset(y: yFor(b.start))
            }
            // Raw sessions: solid box drawn INSET inside its billed block(s), so
            // the surrounding 15-min block stays visible around it (nested look).
            ForEach(sessions) { s in
                SessionBox(session: s, height: span(s.start, s.end ?? Date()))
                    .padding(.horizontal, 12)
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
        .background(ActivityPalette.color(session.color).opacity(session.isOpen ? 0.8 : 0.95),
                    in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.6), lineWidth: 0.5))
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

    static func add(months: Int, to date: Date) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: date) ?? date
    }

    /// The 7 days of the week containing `date`, starting on `firstWeekday`.
    static func weekDays(containing date: Date, firstWeekday: Int) -> [Date] {
        var cal = Calendar.current
        cal.firstWeekday = firstWeekday
        let weekday = cal.component(.weekday, from: date)
        let offset = (weekday - firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: date)) ?? date
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    static func weekdayLetter(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEEE" // single letter (S, M, T…)
        return f.string(from: date)
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
