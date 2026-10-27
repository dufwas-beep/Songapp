import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import SwiftUI

/// Spotify-knappen: ett tryck spelar, ett tryck pausar det Spotify redan spelar.
/// Använder Spotifys Web API med inloggning en gång (PKCE, inget lösenord sparas i appen).
/// Kräver Spotify Premium och internet. Appens Client ID klistras in första gången.
@MainActor
@Observable
final class SpotifyController {
    private(set) var isPlaying = false
    private(set) var busy = false
    var errorMessage: String?

    static let redirectURI = "potpurri://spotify-callback"
    private let defaults = UserDefaults.standard

    var clientID: String {
        get { defaults.string(forKey: "spotifyClientID") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "spotifyClientID") }
    }

    var isConnected: Bool {
        refreshToken != nil
    }

    private var accessToken: String? {
        get { defaults.string(forKey: "spotifyAccessToken") }
        set { defaults.set(newValue, forKey: "spotifyAccessToken") }
    }

    private var refreshToken: String? {
        get { defaults.string(forKey: "spotifyRefreshToken") }
        set { defaults.set(newValue, forKey: "spotifyRefreshToken") }
    }

    private var expiry: Date {
        get { defaults.object(forKey: "spotifyExpiry") as? Date ?? .distantPast }
        set { defaults.set(newValue, forKey: "spotifyExpiry") }
    }

    func disconnect() {
        accessToken = nil
        refreshToken = nil
        isPlaying = false
    }

    // MARK: Inloggning (en gång)

    func connect(using session: WebAuthenticationSession) async {
        guard !clientID.isEmpty else { return }
        let verifier = Self.randomVerifier()
        let challenge = Self.challenge(for: verifier)
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: "user-read-playback-state user-modify-playback-state")
        ]
        do {
            let callback = try await session.authenticate(using: components.url!, callbackURLScheme: "potpurri", preferredBrowserSession: .shared)
            guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
                errorMessage = "Spotify godkände inte inloggningen."
                return
            }
            try await requestToken([
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": Self.redirectURI,
                "client_id": clientID,
                "code_verifier": verifier
            ])
        } catch is CancellationError {
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
        } catch {
            errorMessage = "Inloggningen till Spotify misslyckades: \(error.localizedDescription)"
        }
    }

    private func requestToken(_ form: [String: String]) async throws {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw SpotifyError.message("Spotify svarade inte som väntat. Kontrollera Client ID och Redirect URI.")
        }
        accessToken = token
        if let refresh = json["refresh_token"] as? String { refreshToken = refresh }
        expiry = Date().addingTimeInterval(Double(json["expires_in"] as? Int ?? 3600) - 60)
    }

    private func validToken() async throws -> String {
        if let accessToken, Date() < expiry { return accessToken }
        guard let refreshToken else { throw SpotifyError.message("Logga in på Spotify först.") }
        try await requestToken(["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": clientID])
        guard let accessToken else { throw SpotifyError.message("Logga in på Spotify igen.") }
        return accessToken
    }

    // MARK: Spela / pausa

    func toggle() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let token = try await validToken()
            let playing = try await currentlyPlaying(token)
            try await send(playing ? "pause" : "play", token: token)
            isPlaying = !playing
        } catch let SpotifyError.message(text) {
            errorMessage = text
        } catch {
            errorMessage = "Kunde inte nå Spotify: \(error.localizedDescription)"
        }
    }

    private func currentlyPlaying(_ token: String) async throws -> Bool {
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 204 || data.isEmpty {
            throw SpotifyError.message("Ingen Spotify-enhet är aktiv. Öppna Spotify och spela en låt en gång, sedan fungerar knappen.")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["is_playing"] as? Bool ?? false
    }

    private func send(_ command: String, token: String) async throws {
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/\(command)")!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 403 {
            throw SpotifyError.message("Spotify tillåter bara styrning med Premium.")
        }
        guard (200..<300).contains(status) else {
            throw SpotifyError.message("Spotify svarade med fel (\(status)).")
        }
    }

    enum SpotifyError: Error {
        case message(String)
    }

    // MARK: PKCE

    private static func randomVerifier() -> String {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<64).map { _ in characters.randomElement()! })
    }

    private static func challenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
