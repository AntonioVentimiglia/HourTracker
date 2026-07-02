import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        if store.isAuthenticated {
            MainTabView()
        } else {
            LoginView()
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        TabView {
            CalendarTab()
                .tabItem { Label("Calendar", systemImage: "calendar") }
            SummaryTab()
                .tabItem { Label("Summary", systemImage: "chart.bar.fill") }
            RawDataTab()
                .tabItem { Label("Raw Data", systemImage: "list.bullet.rectangle") }
        }
        .tint(.indigo)
        .overlay(alignment: .bottom) { ClockBar() }
    }
}

/// Persistent clock control so clock-in/out is always one tap away in-app,
/// mirroring the Siri actions.
struct ClockBar: View {
    @EnvironmentObject var store: AppStore
    @State private var note = ""
    @State private var showNote = false

    var body: some View {
        HStack(spacing: 12) {
            if let open = store.openSession, open.isOpen {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Active — \(Format.duration(open.liveDurationSeconds))")
                        .font(.subheadline.bold())
                    if let n = open.note, !n.isEmpty {
                        Text(n).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Button("Clock Out") { Task { await store.clockOut(note: nil) } }
                    .buttonStyle(.borderedProminent).tint(.red)
            } else {
                Text("Not clocked in").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button("Clock In") { Task { await store.clockIn(note: note.isEmpty ? nil : note); note = "" } }
                    .buttonStyle(.borderedProminent).tint(.green)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.bottom, 52) // sit above the tab bar
    }
}
