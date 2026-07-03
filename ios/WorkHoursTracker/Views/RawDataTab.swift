import SwiftUI

struct RawDataTab: View {
    @EnvironmentObject var store: AppStore
    @State private var showing = 0 // 0 sessions, 1 events

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Data", selection: $showing) {
                    Text("Sessions").tag(0); Text("Events").tag(1)
                }
                .pickerStyle(.segmented).padding()

                ScrollView {
                    LazyVStack(spacing: 10) {
                        if showing == 0 {
                            if store.sessions.isEmpty { emptyState("No sessions yet.") }
                            ForEach(store.sessions) { SessionRawRow(session: $0) }
                        } else {
                            if store.events.isEmpty { emptyState("No events yet.") }
                            ForEach(store.events) { EventRawRow(event: $0) }
                        }
                    }
                    .padding(.horizontal)
                    Color.clear.frame(height: 140)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Raw Data")
            .task { await store.refreshAll() }
        }
    }

    func emptyState(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

struct SessionRawRow: View {
    var session: WorkSession
    var body: some View {
        Card {
            HStack {
                Text(Format.timeRange(session)).font(.subheadline.weight(.semibold))
                Spacer()
                Chip(text: session.status, color: statusColor)
            }
            HStack(spacing: 16) {
                labeled("Duration", Format.duration(session.durationSeconds ?? session.liveDurationSeconds))
                labeled("Source", session.source.capitalized)
            }
            if let note = session.note, !note.isEmpty {
                labeled("Note", note)
            }
            Text(session.startTimezoneId).font(.caption2).foregroundStyle(.tertiary)
            if !session.validationWarnings.isEmpty {
                Label(session.validationWarnings.joined(separator: ", "),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    func labeled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
            Text(value).font(.subheadline)
        }
    }

    var statusColor: Color {
        switch session.status {
        case "open": return .green
        case "closed": return .indigo
        case "deleted": return .red
        default: return .orange
        }
    }
}

struct EventRawRow: View {
    var event: ClockEvent
    var body: some View {
        Card {
            HStack {
                Text(prettyType).font(.subheadline.weight(.semibold))
                Spacer()
                SourceIcon(source: event.source)
                Text(event.source.capitalized).font(.caption).foregroundStyle(.secondary)
            }
            if let d = ISO8601.date(event.timestampUtc) {
                Text(Format.time(d)).font(.caption).foregroundStyle(.secondary)
            }
            if let note = event.note, !note.isEmpty {
                Text(note).font(.caption)
            }
            Text("\(event.localDate) · \(event.timezoneId)")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // "clock_in" -> "Clock In"
    var prettyType: String {
        event.type.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }
}
