import SwiftUI

struct SessionEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    var session: WorkSession?
    /// For a new session, the day to default the start/end onto (the calendar's
    /// currently "chosen" day). Ignored when editing an existing session.
    var defaultDate: Date? = nil

    @State private var start = Date()
    @State private var end = Date()
    @State private var hasEnd = true
    @State private var note = ""
    @State private var color: String? = nil   // nil = default indigo

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
                Section("Color") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ColorSwatch(color: Palette.raw, label: "Default",
                                        selected: (color ?? "").isEmpty) { color = nil }
                            ForEach(ActivityPalette.options, id: \.hex) { opt in
                                ColorSwatch(color: Color(hex: opt.hex), label: opt.name,
                                            selected: color == opt.hex) { color = opt.hex }
                            }
                        }
                        .padding(.vertical, 4)
                    }
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
            color = (s.color?.isEmpty == false) ? s.color : nil
        } else if let d = defaultDate {
            let cal = Calendar.current
            start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d
            end = cal.date(bySettingHour: 9, minute: 15, second: 0, of: d) ?? d
        } else {
            start = Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date()
            end = Date()
        }
    }

    func save() async {
        if let s = session {
            await store.updateSession(s.id, start: start, end: hasEnd ? end : nil, note: note, color: color)
        } else {
            _ = try? await APIClient.shared.createSession(startUtc: ISO8601.string(start),
                                                          endUtc: hasEnd ? ISO8601.string(end) : nil,
                                                          note: note, color: color)
            await store.refreshAll()
        }
        dismiss()
    }
}

/// A tappable color choice in the editor.
struct ColorSwatch: View {
    var color: Color
    var label: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(color).frame(width: 34, height: 34)
                    if selected {
                        Circle().stroke(color, lineWidth: 2).frame(width: 42, height: 42)
                        Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                    }
                }
                .frame(height: 44)
                Text(label).font(.caption2).foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
