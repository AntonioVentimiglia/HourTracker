import SwiftUI

struct SummaryTab: View {
    @EnvironmentObject var store: AppStore
    @State private var scope = 1 // 0 day, 1 week, 2 month

    var body: some View {
        NavigationStack {
            ScrollView {
                Picker("Scope", selection: $scope) {
                    Text("Day").tag(0); Text("Week").tag(1); Text("Month").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                if scope == 0 { dailyCard }
                else if scope == 1 { weeklyCard }
                else { monthlyCard }

                Color.clear.frame(height: 140)
            }
            .navigationTitle("Summary")
            .task { await store.refreshAll() }
        }
    }

    var dailyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatRow(label: "Total today", value: store.daily?.allocatedHuman ?? "0m")
            StatRow(label: "Sessions", value: "\(store.daily?.sessionCount ?? 0)")
            if let first = store.daily?.firstClockIn, let d = ISO8601.date(first) {
                StatRow(label: "First clock-in", value: Format.time(d))
            }
            if let last = store.daily?.lastClockOut, let d = ISO8601.date(last) {
                StatRow(label: "Last clock-out", value: Format.time(d))
            }
            if (store.daily?.openSessions ?? 0) > 0 {
                warning("An open session is still running.")
            }
            notesCard(store.daily?.notes ?? [])
        }.padding()
    }

    var weeklyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatRow(label: "Total this week", value: store.weekly?.totalHuman ?? "0m")
            StatRow(label: "Sessions", value: "\(store.weekly?.sessionCount ?? 0)")
            StatRow(label: "Average per active day", value: store.weekly?.averagePerDayHuman ?? "0m")
            if let longest = store.weekly?.longestDay {
                StatRow(label: "Longest day", value: "\(longest.date) · \(longest.human)")
            }
            Text("Daily breakdown").font(.headline).padding(.top, 4)
            ForEach(store.weekly?.dailyBreakdown ?? []) { d in
                BarRow(label: d.date, seconds: d.seconds,
                       maxSeconds: store.weekly?.dailyBreakdown.map(\.seconds).max() ?? 1)
            }
            notesCard(store.weekly?.notes ?? [])
        }.padding()
    }

    var monthlyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Month view aggregates from the same records.")
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(store.weekly?.dailyBreakdown ?? []) { d in
                BarRow(label: d.date, seconds: d.seconds,
                       maxSeconds: store.weekly?.dailyBreakdown.map(\.seconds).max() ?? 1)
            }
        }.padding()
    }

    func notesCard(_ notes: [String]) -> some View {
        Group {
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes / tasks").font(.headline)
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, n in
                        Text("• \(n)").font(.subheadline)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding().background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline).foregroundStyle(.orange)
    }
}

struct StatRow: View {
    var label: String; var value: String
    var body: some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).font(.headline) }
            .padding(.vertical, 4)
    }
}

struct BarRow: View {
    var label: String; var seconds: Int; var maxSeconds: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(label).font(.caption); Spacer(); Text(Format.duration(seconds)).font(.caption).foregroundStyle(.indigo) }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.indigo.opacity(0.7))
                    .frame(width: geo.size.width * CGFloat(seconds) / CGFloat(max(maxSeconds, 1)))
            }
            .frame(height: 8)
        }
    }
}
