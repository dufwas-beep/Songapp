import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import SwiftUI
import UIKit

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
        } catch SpotifyError.rejected {
            errorMessage = "Spotify godkände inte inloggningen. Kontrollera Client ID och Redirect URI."
        } catch let SpotifyError.message(text) {
            errorMessage = text
        } catch {
            errorMessage = "Inloggningen till Spotify misslyckades: \(error.localizedDescription)"
        }
    }

    private func requestToken(_ form: [String: String]) async throws {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 400/401 = inloggningen godkänns inte längre. Annat (t.ex. 5xx) är tillfälligt.
        if status == 400 || status == 401 { throw SpotifyError.rejected }
        guard status == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw SpotifyError.message("Spotify svarade inte som väntat (\(status)). Försök igen om en stund.")
        }
        accessToken = token
        if let refresh = json["refresh_token"] as? String { refreshToken = refresh }
        expiry = Date().addingTimeInterval(Double(json["expires_in"] as? Int ?? 3600) - 60)
    }

    /// Pågående förnyelse av inloggningen. Spotify byter refresh-token vid varje förnyelse,
    /// så två förnyelser samtidigt (t.ex. när appen öppnas och knappen trycks) skulle
    /// annars logga ut en. Alla väntar därför på samma förnyelse.
    @ObservationIgnored private var refreshTask: Task<Void, Error>?

    private func validToken() async throws -> String {
        if let accessToken, Date() < expiry { return accessToken }
        let task: Task<Void, Error>
        if let running = refreshTask {
            task = running
        } else {
            guard let refreshToken else { throw SpotifyError.message("Logga in på Spotify först.") }
            task = Task {
                defer { self.refreshTask = nil }
                try await self.requestToken(["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": self.clientID])
            }
            refreshTask = task
        }
        do {
            try await task.value
        } catch SpotifyError.rejected {
            // Inloggningen har dragits tillbaka – logga in igen nästa tryck.
            disconnect()
            throw SpotifyError.message("Inloggningen till Spotify har gått ut. Tryck på Spotify-knappen och logga in igen.")
        }
        guard let accessToken else { throw SpotifyError.message("Logga in på Spotify igen.") }
        return accessToken
    }

    /// Ett anrop till Spotifys spelare. Försöker en gång till om inloggningen just gått ut
    /// eller nätet hackar till.
    private func call(_ path: String, method: String = "GET", json: [String: Any]? = nil) async throws -> (Data, Int) {
        var attempt = 0
        while true {
            attempt += 1
            let token = try await validToken()
            var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player\(path)")!)
            request.httpMethod = method
            request.timeoutInterval = 10
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let json {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: json)
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 401 {
                    expiry = .distantPast
                    if attempt < 2 { continue }
                    throw SpotifyError.message("Spotify behövde logga in på nytt. Tryck en gång till.")
                }
                if status == 403 { throw SpotifyError.message("Spotify tillåter bara styrning med Premium.") }
                return (data, status)
            } catch let error as URLError where attempt < 2 && error.code != .notConnectedToInternet {
                try await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    /// Läser av om Spotify spelar just nu, så att knappen visar rätt (t.ex. när appen öppnas).
    func refreshState() async {
        guard isConnected, !busy else { return }
        if let playing = try? await playerState() { isPlaying = playing }
    }

    // MARK: Spela / pausa

    /// Spotify-appen öppnades för att vakna – spela när man kommer tillbaka till Potpurri.
    @ObservationIgnored private var playAfterWake = false

    func toggle() async {
        await perform {
            if let playing = try await self.playerState() {
                try await self.command(playing ? "pause" : "play")
                self.isPlaying = !playing
            } else {
                // Ingen aktiv enhet (Spotify har somnat): väck en enhet och spela där.
                try await self.wakeDevice()
            }
        }
    }

    /// Nästa (+1) eller föregående (−1) låt i Spotify.
    func skip(_ step: Int) async {
        await perform {
            if try await self.playerState() == nil {
                try await self.wakeDevice()
                guard self.isPlaying else { return }
            }
            try await self.command(step > 0 ? "next" : "previous", method: "POST")
            self.isPlaying = true
        }
    }

    /// Anropas när Potpurri blir aktiv igen. Har Spotify-appen just väckts startar musiken.
    func appBecameActive() async {
        guard playAfterWake else {
            await refreshState()
            return
        }
        playAfterWake = false
        // Spotify behöver en kort stund för att anmäla sig som enhet.
        try? await Task.sleep(for: .seconds(1))
        await perform {
            for attempt in 1...3 {
                if try await self.transferToDevice() { return }
                if attempt < 3 { try await Task.sleep(for: .seconds(1.5)) }
            }
            throw SpotifyError.message("Spotify vaknade inte. Tryck på knappen igen.")
        }
    }

    private func perform(_ action: @MainActor () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await action()
        } catch let SpotifyError.message(text) {
            errorMessage = text
        } catch is CancellationError {
        } catch {
            errorMessage = "Kunde inte nå Spotify: \(error.localizedDescription)"
        }
    }

    /// Spelar Spotify? nil = ingen aktiv enhet.
    private func playerState() async throws -> Bool? {
        let (data, status) = try await call("")
        if status == 204 || data.isEmpty || !(200..<300).contains(status) { return nil }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard json?["device"] != nil else { return nil }
        return json?["is_playing"] as? Bool ?? false
    }

    /// Väcker Spotify och spelar. Finns ingen enhet alls (iPadOS har stängt av Spotify
    /// i bakgrunden) öppnas Spotify-appen en kort stund; musiken startar när man
    /// kommer tillbaka till Potpurri.
    private func wakeDevice() async throws {
        if try await transferToDevice() { return }
        playAfterWake = true
        if let url = URL(string: "spotify:"), await UIApplication.shared.open(url) { return }
        playAfterWake = false
        throw SpotifyError.message("Spotify är inte igång på någon enhet. Öppna Spotify-appen en kort stund och tryck igen.")
    }

    /// Flyttar uppspelningen till en enhet (helst iPaden) och startar den.
    /// false = ingen enhet svarade.
    private func transferToDevice() async throws -> Bool {
        let (data, _) = try await call("/devices")
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let devices = json?["devices"] as? [[String: Any]] ?? []
        let preferred = devices.first { ($0["type"] as? String) == "Tablet" }
            ?? devices.first { ($0["is_active"] as? Bool) == true }
            ?? devices.first
        guard let id = preferred?["id"] as? String else { return false }
        let (_, status) = try await call("", method: "PUT", json: ["device_ids": [id], "play": true])
        // 404 = enheten har somnat trots att den finns i listan.
        if status == 404 { return false }
        guard (200..<300).contains(status) else {
            throw SpotifyError.message("Spotify kunde inte starta (\(status)). Öppna Spotify-appen en kort stund och tryck igen.")
        }
        isPlaying = true
        return true
    }

    private func command(_ name: String, method: String = "PUT") async throws {
        let (_, status) = try await call("/\(name)", method: method)
        if status == 404 {
            // Enheten somnade mellan anropen. Paus behöver inget mer – annars väcks den.
            if name == "pause" { isPlaying = false } else { try await wakeDevice() }
            return
        }
        guard (200..<300).contains(status) else {
            throw SpotifyError.message("Spotify svarade med fel (\(status)).")
        }
    }

    enum SpotifyError: Error {
        case message(String)
        /// Spotify godkänner inte inloggningen längre.
        case rejected
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
