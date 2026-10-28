import AuthenticationServices
import SwiftUI

/// Spotify-knappen bland de flytande knapparna: ett tryck spelar, ett tryck pausar.
/// Första gången: klistra in appens Client ID och logga in hos Spotify (en gång).
struct SpotifyButton: View {
    @Environment(SpotifyController.self) private var spotify
    @Environment(\.webAuthenticationSession) private var authSession
    @State private var showsSetup = false
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(Feature.spotify.key) private var enabled = true

    var body: some View {
        // Går att stänga av under kugghjulet → Funktioner.
        if enabled { controls }
    }

    private var controls: some View {
        HStack(spacing: 2) {
            skipButton(-1)
            Button {
                run { await spotify.toggle() }
            } label: {
                ZStack {
                    Circle().fill(Color(red: 0.12, green: 0.84, blue: 0.38)).frame(width: 40, height: 40)
                    if spotify.busy {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: spotify.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
            }
            .accessibilityLabel(spotify.isPlaying ? "Pausa Spotify" : "Spela Spotify")
            skipButton(1)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .frame(height: 56)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .guideSpot(.spotify)
        // Håll in för att logga in igen eller koppla från.
        .contextMenu {
            Button {
                showsSetup = true
            } label: {
                Label("Spotify-inloggning", systemImage: "person.badge.key")
            }
        }
        .task { await spotify.refreshState() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await spotify.appBecameActive() } }
        }
        .sheet(isPresented: $showsSetup) {
            SpotifySetup()
        }
        .alert("Spotify", isPresented: Binding(get: { spotify.errorMessage != nil }, set: { if !$0 { spotify.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(spotify.errorMessage ?? "")
        }
    }

    /// Första gången öppnas inloggningen i stället.
    private func run(_ action: @escaping @MainActor @Sendable () async -> Void) {
        if spotify.clientID.isEmpty || !spotify.isConnected {
            showsSetup = true
        } else {
            Task { await action() }
        }
    }

    private func skipButton(_ step: Int) -> some View {
        Button {
            run { await spotify.skip(step) }
        } label: {
            Image(systemName: step > 0 ? "forward.fill" : "backward.fill")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(spotify.busy)
        .accessibilityLabel(step > 0 ? "Nästa låt i Spotify" : "Föregående låt i Spotify")
    }
}

/// Första gången: Client ID från developer.spotify.com och inloggning.
private struct SpotifySetup: View {
    @Environment(SpotifyController.self) private var spotify
    @Environment(\.webAuthenticationSession) private var authSession
    @Environment(\.dismiss) private var dismiss
    @State private var clientID = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Client ID", text: $clientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                } header: {
                    Text("Client ID")
                } footer: {
                    Text("Finns under Settings för appen Potpurri på developer.spotify.com/dashboard. Redirect URI ska vara \(SpotifyController.redirectURI).")
                }
                Section {
                    Button {
                        spotify.clientID = clientID
                        Task {
                            await spotify.connect(using: authSession)
                            if spotify.isConnected { dismiss() }
                        }
                    } label: {
                        Label(spotify.isConnected ? "Logga in igen" : "Logga in hos Spotify", systemImage: "person.badge.key")
                    }
                    .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty)
                } footer: {
                    Text("Du loggar in en gång. Spotify Premium krävs för att styra uppspelningen, och iPaden behöver internet.")
                }
                if spotify.isConnected {
                    Section {
                        Button("Koppla från Spotify", role: .destructive) {
                            spotify.disconnect()
                        }
                    }
                }
            }
            .navigationTitle("Koppla Spotify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng") { dismiss() }
                }
            }
            .onAppear { clientID = spotify.clientID }
        }
    }
}
