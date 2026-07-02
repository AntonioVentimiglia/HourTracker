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
        .overlay(alignment: .top) { ErrorBanner(message: $store.errorMessage) }
    }
}

/// Surfaces any background sync failure (login excluded — that has its own
/// inline message) so a failed refresh is never silent.
struct ErrorBanner: View {
    @Binding var message: String?

    var body: some View {
        if let message {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(message).font(.subheadline)
                Spacer()
                Button {
                    self.message = nil
                } label: { Image(systemName: "xmark") }
            }
            .padding(12)
            .background(.orange, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(duration: 0.3), value: message)
            .task {
                try? await Task.sleep(for: .seconds(5))
                self.message = nil
            }
        }
    }
}

/// Persistent clock control so clock-in/out is always one tap away in-app,
/// mirroring the Siri actions.
struct ClockBar: View {
    @EnvironmentObject var store: AppStore
    @State private var showNote = false
    @State private var showDetail = false

    var body: some View {
        HStack(spacing: 12) {
            if let open = store.openSession, open.isOpen {
                Button { showDetail = true } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text("Active — \(Format.liveClock(open.liveDurationSeconds))")
                                .font(.subheadline.bold())
                                .monospacedDigit()
                        }
                        if let n = open.note, !n.isEmpty {
                            Text(n).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Button("Clock Out") { showNote = true }
                    .buttonStyle(.borderedProminent).tint(.red)
            } else {
                Text("Not clocked in").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button("Clock In") { showNote = true }
                    .buttonStyle(.borderedProminent).tint(.green)
            }
        }
        .sheet(isPresented: $showNote) {
            if let open = store.openSession, open.isOpen {
                NoteEntrySheet(
                    title: "Clock Out",
                    placeholder: (open.note?.isEmpty == false)
                        ? "Any additional notes to add?"
                        : "No note added — what did you work on?"
                ) { enteredNote in
                    Task { await store.clockOut(note: enteredNote) }
                }
            } else {
                NoteEntrySheet(title: "Clock In", placeholder: "What are you working on? (optional)") { enteredNote in
                    Task { await store.clockIn(note: enteredNote) }
                }
            }
        }
        .sheet(isPresented: $showDetail) {
            if let open = store.openSession {
                SessionDetailSheet(session: open)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.bottom, 52) // sit above the tab bar
    }
}

/// Read-only detail view for the active session, shown when tapping the clock bar.
struct SessionDetailSheet: View {
    var session: WorkSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Current session") {
                    LabeledContent("Status", value: session.isOpen ? "Active" : session.status.capitalized)
                    LabeledContent("Started", value: Format.time(session.start))
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        LabeledContent("Elapsed", value: Format.liveClock(session.liveDurationSeconds))
                    }
                    LabeledContent("Timezone", value: session.startTimezoneId)
                    LabeledContent("Source", value: session.source.capitalized)
                }
                if let note = session.note, !note.isEmpty {
                    Section("Note") { Text(note) }
                }
                if !session.validationWarnings.isEmpty {
                    Section("Warnings") {
                        ForEach(session.validationWarnings, id: \.self) { Text($0) }
                    }
                }
            }
            .navigationTitle("Clock-In Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
