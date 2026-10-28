import SwiftData
import SwiftUI
import WebKit

/// "Sök på webben" när låten inte finns i biblioteket. Två vägar utan att lämna appen:
/// direktträffar från en låttextdatabas, eller en inbyggd webbläsare (Google) där man
/// markerar texten och lägger till den som en ny låt. Bara text hämtas – inga ackord.
struct WebSearchSheet: View {
    let initialQuery: String
    let onAdded: (Song) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var tab = Tab.database
    @State private var query = ""
    @State private var results: [LyricsResult] = []
    @State private var searching = false
    @State private var message: String?
    @State private var preview: LyricsResult?
    @State private var web = WebController()
    @State private var newTitle = ""
    @State private var pendingText: String?
    @AppStorage("webLyricsSite") private var site = WebController.Site.google

    private let source: LyricsSource = LRCLIBSource()

    enum Tab {
        case database
        case web
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    SearchField(text: $query, prompt: "Låt eller rad ur texten")
                        .onSubmit(search)
                    Button("Sök", action: search)
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(.black)
                }
                .padding(12)
                Picker("Källa", selection: $tab) {
                    Text("Låttexter").tag(Tab.database)
                    Text("Webben").tag(Tab.web)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                Divider()
                switch tab {
                case .database:
                    databaseView
                case .web:
                    WebView(view: web.view(for: site))
                        .id(site)
                        .safeAreaInset(edge: .top) {
                            // Välj var på webben det söks: Google, AZLyrics eller Genius.
                            Picker("Sök på", selection: $site) {
                                ForEach(WebController.Site.allCases, id: \.self) { site in
                                    Text(site.label).tag(site)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.bar)
                        }
                        .safeAreaInset(edge: .bottom) {
                            Button {
                                Task { await addFromPage() }
                            } label: {
                                Label("Hämta låttexten från sidan", systemImage: "text.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .foregroundStyle(.black)
                            .controlSize(.large)
                            .padding(12)
                            .background(.bar)
                        }
                }
            }
            .navigationTitle("Sök på webben")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng") { dismiss() }
                }
            }
            .onAppear {
                query = initialQuery
                search()
            }
            // Texten från sidan visas först så att man kan rätta den innan låten läggs till.
            .sheet(isPresented: Binding(get: { pendingText != nil }, set: { if !$0 { pendingText = nil } })) {
                NavigationStack {
                    Form {
                        Section("Titel") {
                            TextField("Titel", text: $newTitle)
                        }
                        Section("Låttext – rätta vid behov") {
                            TextEditor(text: Binding(get: { pendingText ?? "" }, set: { pendingText = $0 }))
                                .frame(minHeight: 360)
                        }
                    }
                    .navigationTitle("Ny låt")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Avbryt") { pendingText = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Lägg till") {
                                if let text = pendingText {
                                    pendingText = nil
                                    add(title: newTitle, artist: "", lyrics: text)
                                }
                            }
                        }
                    }
                }
            }
            .alert("Sök på webben", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var databaseView: some View {
        List {
            if searching {
                HStack { ProgressView(); Text("Söker …").foregroundStyle(.secondary) }
            } else if results.isEmpty {
                Text("Inga träffar. Prova Webben (Google) ovan.")
                    .foregroundStyle(.secondary)
            }
            ForEach(results) { result in
                Button {
                    preview = result
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title).font(.headline)
                        Text(result.artist).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .sheet(item: $preview) { result in
            NavigationStack {
                ScrollView {
                    Text(result.lyrics)
                        .font(.title3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                        .textSelection(.enabled)
                }
                .navigationTitle(result.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Tillbaka") { preview = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Lägg till") {
                            preview = nil
                            add(title: result.title, artist: result.artist, lyrics: result.lyrics)
                        }
                    }
                }
            }
        }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        Task { await web.loadAll(q) }
        Task {
            do {
                results = try await source.search(q)
            } catch {
                results = []
                message = "Låttextdatabasen svarade inte. Kontrollera internet, eller prova Webben (Google)."
            }
            searching = false
        }
    }

    /// Hämtar låttexten från sidan: markerad text om man markerat något, annars letar
    /// appen själv upp textblocket som ser ut som en låttext (t.ex. Googles låttextruta
    /// eller texten på AZLyrics). Texten visas för kontroll innan den läggs till.
    private func addFromPage() async {
        var text = await web.selectedText()
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = await web.findLyrics()
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "Hittade ingen låttext på sidan. Öppna en sida med texten, eller markera texten (håll in och dra) och tryck igen."
            return
        }
        newTitle = query.trimmingCharacters(in: .whitespaces)
        pendingText = text
    }

    /// Den nya låten blir en textlåt; titel och artist fylls i, ackord läggs med ackordstämplarna.
    private func add(title: String, artist: String, lyrics: String) {
        let name = title.trimmingCharacters(in: .whitespaces).isEmpty ? query : title
        let header = artist.isEmpty ? "" : "Artist: \(artist)\n\n"
        let song = Song(title: name, kind: .text, text: header + lyrics)
        context.insert(song)
        try? context.save()
        onAdded(song)
        dismiss()
    }
}

/// Styr den inbyggda webbläsaren. Varje sajt har en egen flik som laddas direkt vid
/// sökningen, så att det går snabbt att växla mellan Google, AZLyrics och Genius.
@MainActor
final class WebController {
    private var views: [Site: WKWebView] = [:]
    private var current: Site = .google

    func view(for site: Site) -> WKWebView {
        current = site
        if let view = views[site] { return view }
        let view = WKWebView()
        blockAds(in: view)
        view.allowsBackForwardNavigationGestures = true
        views[site] = view
        return view
    }

    private var blocking: Set<ObjectIdentifier> = []

    private func blockAds(in view: WKWebView) {
        guard let rules = AdBlock.rules, !blocking.contains(ObjectIdentifier(view)) else { return }
        view.configuration.userContentController.add(rules)
        blocking.insert(ObjectIdentifier(view))
    }

    /// Fliken som visas just nu.
    private var currentView: WKWebView {
        view(for: current)
    }

    /// Sajter man kan söka på i webbläsaren.
    enum Site: String, CaseIterable {
        case google
        case azlyrics
        case genius

        var label: String {
            switch self {
            case .google: return "Google"
            case .azlyrics: return "AZLyrics"
            case .genius: return "Genius"
            }
        }

        func url(for query: String) -> URL? {
            var components: URLComponents?
            switch self {
            case .google:
                components = URLComponents(string: "https://www.google.com/search")
                components?.queryItems = [URLQueryItem(name: "q", value: query + " lyrics")]
            case .azlyrics:
                components = URLComponents(string: "https://search.azlyrics.com/search.php")
                components?.queryItems = [URLQueryItem(name: "q", value: query)]
            case .genius:
                components = URLComponents(string: "https://genius.com/search")
                components?.queryItems = [URLQueryItem(name: "q", value: query)]
            }
            return components?.url
        }
    }

    /// Sökningen laddas på alla sajter samtidigt (i bakgrunden). Reklamspärren förbereds först.
    func loadAll(_ query: String) async {
        await AdBlock.prepare()
        for view in views.values { blockAds(in: view) }
        let showing = current
        for site in Site.allCases {
            if let url = site.url(for: query) { view(for: site).load(URLRequest(url: url)) }
        }
        current = showing
    }

    func selectedText() async -> String {
        (try? await currentView.evaluateJavaScript("window.getSelection().toString()") as? String) ?? ""
    }

    /// Letar upp det textblock på sidan som mest liknar en låttext: många korta rader och
    /// nästan inga länkar. Det minsta sådana blocket vinner (inte hela sidan runt omkring).
    func findLyrics() async -> String {
        let script = """
        (function() {
          let best = null, bestScore = 0;
          document.querySelectorAll('div, p, pre, section, article, span').forEach(function(el) {
            const text = el.innerText || '';
            if (text.length < 80 || text.length > 12000) return;
            const lines = text.split('\\n').map(function(l) { return l.trim(); }).filter(function(l) { return l.length > 0; });
            if (lines.length < 6) return;
            const short = lines.filter(function(l) { return l.length < 70; }).length;
            if (short / lines.length < 0.85) return;
            const links = el.querySelectorAll('a').length;
            if (links > 2) return;
            const score = short * 1000 - text.length / 50;
            if (score > bestScore || (score === bestScore && best && best.contains(el))) {
              bestScore = score; best = el;
            }
          });
          return best ? best.innerText.trim() : '';
        })();
        """
        return (try? await currentView.evaluateJavaScript(script) as? String) ?? ""
    }
}

private struct WebView: UIViewRepresentable {
    let view: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}

/// Enkel reklamspärr för webbläsaren: stoppar de vanligaste annonsnätverken, så att
/// låttextsidorna blir lättare att läsa.
@MainActor
enum AdBlock {
    private(set) static var rules: WKContentRuleList?
    private static var tried = false

    private static let domains = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "adservice.google.com",
        "google-analytics.com", "googletagmanager.com", "googletagservices.com", "amazon-adsystem.com",
        "adnxs.com", "taboola.com", "outbrain.com", "criteo.com", "criteo.net", "pubmatic.com",
        "rubiconproject.com", "openx.net", "casalemedia.com", "moatads.com", "scorecardresearch.com",
        "quantserve.com", "advertising.com", "adsrvr.org", "smartadserver.com", "teads.tv",
        "media.net", "yieldmo.com", "sharethrough.com", "33across.com", "indexww.com", "primis.tech",
        "connatix.com", "ex.co", "vidazoo.com", "adform.net", "3lift.com", "triplelift.com"
    ]

    static func prepare() async {
        guard !tried else { return }
        tried = true
        // Blockera förfrågningar *till* annonsnätverken (inte sidor på dem).
        let json = "[" + domains.map { domain in
            "{\"trigger\":{\"url-filter\":\"^https?://([^/]+\\\\.)?\(domain.replacingOccurrences(of: ".", with: "\\\\."))[:/]\"},\"action\":{\"type\":\"block\"}}"
        }.joined(separator: ",") + "]"
        rules = try? await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "PotpurriAdBlock", encodedContentRuleList: json)
    }
}
