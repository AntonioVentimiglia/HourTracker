import SwiftUI

struct SessionEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    var session: WorkSession?

    @State private var start = Date()
    @State private var end = Date()
    @State private var hasEnd = true
    @State private var note = ""

    var isNew: Bool { session == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Time") {
                    DatePicker("Start", selection: $start)
                    Toggle("Has end time", isOn: $hasEnd)
                    if hasEnd { DatePicker("End", selection: $end) }
                }
                Section("Note") {
                    TextField("What were you working on?", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                if hasEnd && end <= start {
                    Text("End time must be after start time.")
                        .font(.caption).foregroundStyle(.red)
                }
                if !isNew {
                    Section {
                        Button("Delete session", role: .destructive) {
                            Task { if let s = session { await store.deleteSession(s); dismiss() } }
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New Session" : "Edit Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(hasEnd && end <= start)
                }
            }
            .onAppear(perform: load)
        }
    }

    func load() {
        if let s = session {
            start = s.start
            if let e = s.end { end = e; hasEnd = true } else { hasEnd = false; end = Date() }
            note = s.note ?? ""
        } else {
            start = Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date()
            end = Date()
        }
    }

    func save() async {
        if let s = session {
            await store.updateSession(s.id, start: start, end: hasEnd ? end : nil, note: note)
        } else {
            _ = try? await APIClient.shared.createSession(startUtc: ISO8601.string(start),
                                                          endUtc: hasEnd ? ISO8601.string(end) : nil,
                                                          note: note)
            await store.refreshAll()
        }
        dismiss()
    }
}
