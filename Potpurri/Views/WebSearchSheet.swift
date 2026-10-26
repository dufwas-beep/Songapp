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
                    Text("Webben (Google)").tag(Tab.web)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                Divider()
                switch tab {
                case .database:
                    databaseView
                case .web:
                    WebView(controller: web)
                        .safeAreaInset(edge: .bottom) {
                            Button {
                                Task { await addSelection() }
                            } label: {
                                Label("Lägg till markerad text som ny låt", systemImage: "plus")
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
            .alert("Ny låt", isPresented: Binding(get: { pendingText != nil }, set: { if !$0 { pendingText = nil } })) {
                TextField("Titel", text: $newTitle)
                Button("Avbryt", role: .cancel) {}
                Button("Lägg till") {
                    if let text = pendingText { add(title: newTitle, artist: "", lyrics: text) }
                }
            } message: {
                Text("Vad ska låten heta?")
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
        web.load(q)
        searching = true
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

    /// Markerad text i webbläsaren blir en ny låt.
    private func addSelection() async {
        let text = await web.selectedText()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "Markera texten på sidan först (håll in och dra), och tryck sedan igen."
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

/// Styr den inbyggda webbläsaren.
@MainActor
final class WebController {
    let view: WKWebView = {
        let view = WKWebView()
        view.allowsBackForwardNavigationGestures = true
        return view
    }()

    func load(_ query: String) {
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query + " lyrics")]
        if let url = components.url { view.load(URLRequest(url: url)) }
    }

    func selectedText() async -> String {
        (try? await view.evaluateJavaScript("window.getSelection().toString()") as? String) ?? ""
    }
}

private struct WebView: UIViewRepresentable {
    let controller: WebController

    func makeUIView(context: Context) -> WKWebView {
        controller.view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}
