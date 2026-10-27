import SwiftUI

/// Guiden som visas första gången appen öppnas. Kan visas igen från kugghjulet.
struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Page {
        let symbol: String
        let title: String
        let text: String
    }

    private let pages: [Page] = [
        Page(symbol: "music.note.house", title: "Välkommen till Potpurri",
             text: "Alla dina låtar på ett ställe – PDF:er, bilder och textlåtar med ackord. Här är en snabb rundtur."),
        Page(symbol: "square.and.arrow.down", title: "Lägg in låtar",
             text: "Tryck på + i biblioteket för att hämta PDF:er och bilder från Filer, eller läs in ett OnSong-bibliotek. Sök hittar även texten inne i låtarna."),
        Page(symbol: "list.bullet.rectangle", title: "Låtlistor",
             text: "Gör en låtlista för kvällen. Dra i ≡ för att ändra ordning. Dra en låt åt höger för att lägga den i lådan."),
        Page(symbol: "hand.tap", title: "Spela",
             text: "Tryck på låten eller använd pedalen för att gå vidare. Autoscroll startar med knappen nere till höger. Pilarna uppe till höger byter låt."),
        Page(symbol: "pencil.tip.crop.circle", title: "Penna, notes och ackord",
             text: "Under ⋯ nere till höger finns markeringspenna, notes, hopplinjer och ackord. Ångra och Gör om sitter i verktyget du använder."),
        Page(symbol: "sparkles", title: "Förslag och färger",
             text: "Färgkoderna ger förslag på nästa låt. Spelade låtar blir gråa – tryck Ny spelning när en ny kväll börjar."),
        Page(symbol: "speaker.wave.2", title: "Ljud och Spotify",
             text: "Ljudknappen öppnar en ljudpanel med egna klipp. Spotify-knappen startar och pausar musik mellan låtarna."),
        Page(symbol: "gearshape", title: "Inställningar",
             text: "Kugghjulet uppe till höger har kvällsloggar, säkerhetskopia, grått och mörkt läge och den här guiden igen."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Hoppa över") { dismiss() }
                    .opacity(page < pages.count - 1 ? 1 : 0)
            }
            .padding()
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    let item = pages[index]
                    VStack(spacing: 24) {
                        Spacer()
                        if index == 0 {
                            Image("LPLogo")
                                .resizable()
                                .frame(width: 140, height: 140)
                        } else {
                            Image(systemName: item.symbol)
                                .font(.system(size: 80, weight: .light))
                                .foregroundStyle(Color.accentColor)
                                .frame(height: 140)
                        }
                        Text(item.title)
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text(item.text)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 480)
                        Spacer()
                    }
                    .padding(.horizontal, 32)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    dismiss()
                }
            } label: {
                Text(page < pages.count - 1 ? "Nästa" : "Kör igång!")
                    .font(.headline)
                    .frame(maxWidth: 320)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 32)
        }
    }
}

/// Utseende: följ iPaden, eller alltid ljust, grått (ljust men nedtonat) eller mörkt.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, gray, dark
    var id: Self { self }

    var title: String {
        switch self {
        case .system: "Automatiskt"
        case .light: "Ljust"
        case .gray: "Grått"
        case .dark: "Mörkt"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light, .gray: .light
        case .dark: .dark
        }
    }
}
