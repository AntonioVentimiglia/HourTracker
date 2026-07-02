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

                List {
                    if showing == 0 {
                        ForEach(store.sessions) { s in SessionRawRow(session: s) }
                    } else {
                        ForEach(store.events) { e in EventRawRow(event: e) }
                    }
                    Color.clear.frame(height: 120).listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
            .navigationTitle("Raw Data")
            .task { await store.refreshAll() }
        }
    }
}

struct SessionRawRow: View {
    var session: WorkSession
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(session.id.prefix(8) + "…").font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Text(session.status).font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(statusColor.opacity(0.2), in: Capsule())
                    .foregroundStyle(statusColor)
            }
            Text(Format.timeRange(session)).font(.subheadline.bold())
            Text("Duration: \(Format.duration(session.durationSeconds))").font(.caption)
            Text("TZ: \(session.startTimezoneId) · Source: \(session.source)")
                .font(.caption2).foregroundStyle(.secondary)
            if let note = session.note, !note.isEmpty { Text("Note: \(note)").font(.caption) }
            if !session.validationWarnings.isEmpty {
                Text("⚠︎ " + session.validationWarnings.joined(separator: ", "))
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
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
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(event.type).font(.subheadline.bold())
                Spacer()
                SourceIcon(source: event.source)
            }
            if let d = ISO8601.date(event.timestampUtc) {
                Text(Format.time(d)).font(.caption)
            }
            Text("Local date: \(event.localDate) · TZ: \(event.timezoneId)")
                .font(.caption2).foregroundStyle(.secondary)
            if let note = event.note, !note.isEmpty { Text("Note: \(note)").font(.caption) }
        }
        .padding(.vertical, 4)
    }
}
