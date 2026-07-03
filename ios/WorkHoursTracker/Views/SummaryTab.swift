import SwiftUI

struct SummaryTab: View {
    @EnvironmentObject var store: AppStore
    @State private var scope = 1 // 0 day, 1 week, 2 month

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Scope", selection: $scope) {
                        Text("Day").tag(0); Text("Week").tag(1); Text("Month").tag(2)
                    }
                    .pickerStyle(.segmented)

                    if scope == 0 { dailyCards }
                    else if scope == 1 { weeklyCards }
                    else { monthlyCards }

                    Color.clear.frame(height: 140)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Summary")
            .task { await store.refreshAll() }
        }
    }

    // MARK: Day

    @ViewBuilder var dailyCards: some View {
        let d = store.daily
        BilledVsRawHero(
            billedHuman: d?.billedHuman ?? "0m",
            billedSeconds: d?.billedSeconds ?? 0,
            rawHuman: d?.rawHuman ?? d?.allocatedHuman ?? "0m",
            blockCount: d?.blockCount ?? 0
        )

        Card(title: "Today", systemImage: "sun.max") {
            InfoRow(label: "Sessions", value: "\(d?.sessionCount ?? 0)")
            if let first = d?.firstClockIn, let date = ISO8601.date(first) {
                InfoRow(label: "First clock-in", value: Format.time(date))
            }
            if let last = d?.lastClockOut, let date = ISO8601.date(last) {
                InfoRow(label: "Last clock-out", value: Format.time(date))
            }
            if (d?.openSessions ?? 0) > 0 {
                Label("An open session is still running", systemImage: "record.circle")
                    .font(.subheadline).foregroundStyle(.orange)
            }
        }

        notesCard(d?.notes ?? [])
    }

    // MARK: Week

    @ViewBuilder var weeklyCards: some View {
        let w = store.weekly
        BilledVsRawHero(
            billedHuman: w?.billedHuman ?? "0m",
            billedSeconds: w?.billedSeconds ?? 0,
            rawHuman: w?.rawHuman ?? w?.totalHuman ?? "0m",
            blockCount: w?.blockCount ?? 0
        )

        Card(title: "This week", systemImage: "calendar") {
            InfoRow(label: "Sessions", value: "\(w?.sessionCount ?? 0)")
            InfoRow(label: "Average / active day", value: w?.averagePerDayHuman ?? "0m")
            if let longest = w?.longestDay {
                InfoRow(label: "Longest day", value: "\(shortDay(longest.date)) · \(longest.human)")
            }
        }

        Card(title: "Daily breakdown", systemImage: "chart.bar") {
            let days = w?.dailyBreakdown ?? []
            if days.isEmpty {
                Text("No tracked time this week.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                let maxSec = days.map(\.seconds).max() ?? 1
                ForEach(days) { day in
                    BarRow(label: shortDay(day.date),
                           rawSeconds: day.seconds,
                           billedSeconds: w?.billedByDay?[day.date] ?? 0,
                           maxSeconds: maxSec)
                }
            }
        }

        notesCard(w?.notes ?? [])
    }

    // MARK: Month

    @ViewBuilder var monthlyCards: some View {
        let w = store.weekly
        BilledVsRawHero(
            billedHuman: w?.billedHuman ?? "0m",
            billedSeconds: w?.billedSeconds ?? 0,
            rawHuman: w?.rawHuman ?? w?.totalHuman ?? "0m",
            blockCount: w?.blockCount ?? 0
        )
        Card(title: "About the month view", systemImage: "info.circle") {
            Text("Totals above cover the selected week's records. Use the Calendar tab's Month view to see the full month laid out.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    // MARK: Shared

    @ViewBuilder func notesCard(_ notes: [String]) -> some View {
        if !notes.isEmpty {
            Card(title: "Notes / tasks", systemImage: "note.text") {
                ForEach(Array(notes.enumerated()), id: \.offset) { _, n in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundStyle(.indigo)
                        Text(n).font(.subheadline)
                    }
                }
            }
        }
    }

    func shortDay(_ iso: String) -> String {
        guard let date = DateFormatter.iso8601Day.date(from: iso) else { return iso }
        let f = DateFormatter(); f.dateFormat = "EEE d"
        return f.string(from: date)
    }
}

/// A single day's bar showing raw time (light) with the billed amount (solid)
/// overlaid, so you can see rounding-up at a glance.
struct BarRow: View {
    var label: String
    var rawSeconds: Int
    var billedSeconds: Int
    var maxSeconds: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption.weight(.medium))
                Spacer()
                Text(Format.duration(rawSeconds)).font(.caption).foregroundStyle(.secondary)
                if billedSeconds > 0 {
                    Text("· \(Format.decimalHours(billedSeconds))")
                        .font(.caption.weight(.semibold)).foregroundStyle(.indigo)
                }
            }
            GeometryReader { geo in
                let scale = CGFloat(max(billedSeconds, maxSeconds, 1))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.indigo.opacity(0.15))
                        .frame(width: geo.size.width * CGFloat(rawSeconds) / scale)
                    Capsule().fill(Color.indigo.opacity(0.55))
                        .frame(width: geo.size.width * CGFloat(billedSeconds) / scale)
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 2)
    }
}

extension DateFormatter {
    static let iso8601Day: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f
    }()
}
