import AuthenticationServices
import SwiftUI

/// Spotify-knappen bland de flytande knapparna: ett tryck spelar, ett tryck pausar.
/// Första gången: klistra in appens Client ID och logga in hos Spotify (en gång).
struct SpotifyButton: View {
    @Environment(SpotifyController.self) private var spotify
    @Environment(\.webAuthenticationSession) private var authSession
    @State private var showsSetup = false

    var body: some View {
        Button {
            if spotify.clientID.isEmpty || !spotify.isConnected {
                showsSetup = true
            } else {
                Task { await spotify.toggle() }
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color(red: 0.12, green: 0.84, blue: 0.38)).frame(width: 34, height: 34)
                    if spotify.busy {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: spotify.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
                Text("Spotify")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.leading, 10)
            .padding(.trailing, 16)
            .frame(height: 56)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spotify.isPlaying ? "Pausa Spotify" : "Spela Spotify")
        .sheet(isPresented: $showsSetup) {
            SpotifySetup()
        }
        .alert("Spotify", isPresented: Binding(get: { spotify.errorMessage != nil }, set: { if !$0 { spotify.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(spotify.errorMessage ?? "")
        }
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
