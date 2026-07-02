import SwiftUI

/// Optional note capture shown when clocking in or out. Skippable — dismissing
/// without saving still lets the clock action through with no note.
struct NoteEntrySheet: View {
    var title: String
    var placeholder: String
    var onComplete: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var textBeforeRecording = ""
    @StateObject private var speech = SpeechRecognizer()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8).padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .scrollContentBackground(.hidden)
                }
                .frame(minHeight: 120)
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 10) {
                    Button {
                        if speech.isRecording {
                            speech.stop()
                        } else {
                            textBeforeRecording = text
                            speech.start()
                        }
                    } label: {
                        Image(systemName: speech.isRecording ? "waveform" : "mic.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                            .frame(width: 88, height: 88)
                            .background(speech.isRecording ? Color.red : Color.indigo, in: Circle())
                            .scaleEffect(speech.isRecording ? 1.08 : 1.0)
                            .animation(.easeInOut(duration: 0.2), value: speech.isRecording)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(speech.isRecording ? "Stop dictation" : "Talk instead of typing")

                    Text(speech.isRecording ? "Listening…" : "Tap to talk instead of typing")
                        .font(.caption).foregroundStyle(.secondary)

                    if let err = speech.errorMessage {
                        Text(err).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { finish(with: nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { finish(with: text) }.bold()
                }
            }
            .onChange(of: speech.transcript) { _, newValue in
                guard !newValue.isEmpty else { return }
                text = textBeforeRecording.isEmpty ? newValue : "\(textBeforeRecording) \(newValue)"
            }
        }
        .presentationDetents([.medium])
        .onDisappear { speech.stop() }
    }

    private func finish(with note: String?) {
        speech.stop()
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        onComplete(trimmed?.isEmpty == false ? trimmed : nil)
        dismiss()
    }
}
