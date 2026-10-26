import Foundation

/// En låttext från en textkälla.
struct LyricsResult: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let lyrics: String
}

/// Varifrån låttexter hämtas. Utbytbar: LRCLIB nu, en licensierad tjänst (t.ex.
/// Musixmatch) kan kopplas in senare utan att resten av appen ändras.
protocol LyricsSource {
    func search(_ query: String) async throws -> [LyricsResult]
}

/// LRCLIB – fri låttextdatabas utan konto (lrclib.net).
struct LRCLIBSource: LyricsSource {
    private struct Item: Decodable {
        let id: Int
        let trackName: String?
        let artistName: String?
        let plainLyrics: String?
    }

    func search(_ query: String) async throws -> [LyricsResult] {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        var request = URLRequest(url: components.url!)
        request.setValue("Potpurri (iPad)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        let items = try JSONDecoder().decode([Item].self, from: data)
        return items.compactMap { item in
            guard let lyrics = item.plainLyrics, !lyrics.isEmpty else { return nil }
            return LyricsResult(id: String(item.id), title: item.trackName ?? query, artist: item.artistName ?? "", lyrics: lyrics)
        }
    }
}
