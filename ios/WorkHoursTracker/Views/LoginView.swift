import SwiftUI

struct LoginView: View {
    @EnvironmentObject var store: AppStore
    @State private var email = "demo@example.com"
    @State private var password = "password123"
    @State private var name = ""
    @State private var registering = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Work Hours")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("Track time with your voice.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)

                    VStack(spacing: 12) {
                        if registering {
                            TextField("Name", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }
                        TextField("Email", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        Task {
                            if registering { await store.register(email: email, password: password, name: name) }
                            else { await store.login(email: email, password: password) }
                        }
                    } label: {
                        Text(registering ? "Create account" : "Log in")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(store.isBusy)

                    Button(registering ? "Have an account? Log in" : "New here? Create an account") {
                        registering.toggle()
                    }
                    .font(.footnote)

                    if let err = store.errorMessage {
                        Text(err).font(.footnote).foregroundStyle(.red)
                    }

                    Divider().padding(.vertical, 8)

                    SiriTips()
                }
                .padding(20)
            }
            .navigationTitle("")
        }
    }
}

struct SiriTips: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Use Siri", systemImage: "mic.fill").font(.headline)
            tip("“Hey Siri, clock me in with Work Hours.”")
            tip("“Hey Siri, clock me out with Work Hours.”")
            tip("“Hey Siri, show today's hours with Work Hours.”")
            Text("Want the shorter “clock me in”? Create a personal shortcut with that name that runs the Clock In action. It's optional.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    func tip(_ text: String) -> some View {
        Text(text).font(.subheadline).italic()
    }
}
