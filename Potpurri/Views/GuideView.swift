import SwiftUI

/// Guiden som visas första gången appen öppnas. Kan visas igen från kugghjulet.
/// Två varianter: en snabbintro om det som är unikt för Potpurri, och hela rundturen.
struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var pages: [Page]?

    struct Page {
        let symbol: String
        let title: String
        let text: String
    }

    static let shortPages: [Page] = [
        Page(symbol: "logo", title: "Det här gör Potpurri unikt",
             text: "Sex saker som gör scenen enklare. En minut, sedan kör vi."),
        Page(symbol: "sparkles", title: "Next",
             text: "Under listorna föreslår Next låtar som passar efter den du spelar, styrt av kategorierna. Tryck på ett förslag för att titta i förhandsrutan – tryck på loggan för en slumpad låt."),
        Page(symbol: "arrow.down.to.line", title: "Hopplinjer",
             text: "Lägg hopplinjer i låten (⋯ → Hopplinjer). Ett tryck i låten eller på pedalen hoppar till nästa linje – perfekt för repriser och långa låtar."),
        Page(symbol: "speaker.wave.2", title: "Soundboard",
             text: "Egna ljudklipp i högerkanten – applåder, jinglar, intron. Ett tryck spelar, ett till stoppar. Spotify styrs från samma ställe."),
        Page(symbol: "music.note", title: "Ackord",
             text: "Lägg ackord ovanpå vilken låt som helst, även PDF:er (⋯ → Ackord). Transponera hela låten med ♭ och ♯."),
        Page(symbol: "tag", title: "Kategorier",
             text: "Märk låtar med upp till sju kategorier, t.ex. Allsång, Lugn och Dans. Tryck på en kategori ovanför listan för att bara se de låtarna."),
        Page(symbol: "tray", title: "Lådan",
             text: "Svep en låt åt höger så hamnar den i Lådan vid kanten – med ett gult fält för egna anteckningar. Bra för en extralåt eller ett quizmanus."),
    ]

    static let fullPages: [Page] = [
        Page(symbol: "logo", title: "Välkommen till Potpurri",
             text: "Alla dina låtar på ett ställe – PDF:er, bilder och textlåtar med ackord. Här är en rundtur."),
        Page(symbol: "square.and.arrow.down", title: "Lägg in låtar",
             text: "Tryck på + i biblioteket för att hämta PDF:er och bilder från Filer, läsa in ett OnSong-bibliotek eller skriva en ny låt. Sök hittar även texten inne i låtarna."),
        Page(symbol: "list.bullet.rectangle", title: "Låtlistor",
             text: "Gör en låtlista för kvällen. Håll in en låt och dra för att ändra ordning. Svep en låt åt höger för att lägga den i Lådan. Quiz-fliken samlar alla quiz."),
        Page(symbol: "hand.tap", title: "Spela",
             text: "Tryck på låten eller använd pedalen för att gå vidare. Nästa och förra låt finns uppe till höger. Autoscroll slås på under ⋯."),
        Page(symbol: "pencil.tip.crop.circle", title: "Penna, notes, hopplinjer och ackord",
             text: "Under ⋯ nere till höger finns markeringspenna, notes, hopplinjer och ackord. Ångra och Gör om sitter i verktyget du använder."),
        Page(symbol: "sparkles", title: "Next och kategorier",
             text: "Kategorierna ger förslag på nästa låt i Next. Spelade låtar blir gråa och en ny spelning börjar av sig själv nästa dag."),
        Page(symbol: "tray", title: "Lådan",
             text: "Lådan vid högerkanten rymmer en låt eller anteckning, med ett gult fält för egna anteckningar."),
        Page(symbol: "speaker.wave.2", title: "Ljud och Spotify",
             text: "Ljudknappen öppnar soundboarden med egna klipp. Spotify-knapparna spelar, pausar och byter låt mellan numren."),
        Page(symbol: "cup.and.saucer", title: "Paus",
             text: "Koppen bredvid Ny spelning startar skärmsläckaren. Tryck på skärmen för att fortsätta."),
        Page(symbol: "gearshape", title: "Inställningar",
             text: "Kugghjulet uppe till höger har kvällsloggar, säkerhetskopia, utseende och den här guiden igen."),
    ]

    var body: some View {
        if let pages {
            tour(pages)
        } else {
            chooser
        }
    }

    /// Första sidan: välj kort eller lång guide.
    private var chooser: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Button("Hoppa över") { dismiss() }
            }
            .padding()
            Spacer()
            Image("LPLogo")
                .resizable()
                .frame(width: 140, height: 140)
            Text("Välkommen till Potpurri")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            VStack(spacing: 12) {
                Button {
                    page = 0
                    pages = Self.shortPages
                } label: {
                    VStack(spacing: 2) {
                        Text("Snabbintro").font(.headline)
                        Text("Det som gör Potpurri unikt – ca 1 minut").font(.footnote)
                    }
                    .frame(maxWidth: 340)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.black)
                Button {
                    page = 0
                    pages = Self.fullPages
                } label: {
                    VStack(spacing: 2) {
                        Text("Hela guiden").font(.headline)
                        Text("Allt från import till inställningar").font(.footnote)
                    }
                    .frame(maxWidth: 340)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func tour(_ pages: [Page]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button("Tillbaka") { self.pages = nil }
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
                        if item.symbol == "logo" {
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

/// Utseende: följ iPaden, eller alltid ljust, grått eller mörkt.
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
        case .light: .light
        case .gray, .dark: .dark
        }
    }
}

/// Grått tema: samma som mörkt läge (ljus text och ljusa symboler) men med grå
/// bakgrunder i stället för svarta. Gråtonen väljs under kugghjulet.
enum Theme {
    static let defaultTone = 0.3

    static func background(_ tone: Double) -> Color { Color(white: tone) }
    /// Rutor ovanpå bakgrunden (t.ex. Next-rutan) – lite ljusare.
    static func raised(_ tone: Double) -> Color { Color(white: tone + 0.08) }
}

/// Grå bakgrund bakom en vy och dess listor när det gråa temat är valt.
struct ThemedBackground: ViewModifier {
    @AppStorage("appearance") private var appearance = Appearance.system
    @AppStorage("grayTone") private var grayTone = Theme.defaultTone

    func body(content: Content) -> some View {
        if appearance == .gray {
            content
                .scrollContentBackground(.hidden)
                .background(Theme.background(grayTone).ignoresSafeArea())
        } else {
            content
        }
    }
}

/// Bakgrunden för en ruta (t.ex. Next-rutan): ljusgrå i ljust läge, ljusare grå i grått.
struct ThemedBox: ViewModifier {
    var cornerRadius: CGFloat = 14
    @AppStorage("appearance") private var appearance = Appearance.system
    @AppStorage("grayTone") private var grayTone = Theme.defaultTone

    func body(content: Content) -> some View {
        content.background(
            appearance == .gray ? Theme.raised(grayTone) : Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: cornerRadius)
        )
    }
}

/// Bakgrunden för en panel (lådan, ljudpanelen): som vanligt, eller grå i grått tema.
struct ThemedPanel: ViewModifier {
    @AppStorage("appearance") private var appearance = Appearance.system
    @AppStorage("grayTone") private var grayTone = Theme.defaultTone

    func body(content: Content) -> some View {
        content.background(appearance == .gray ? Theme.raised(grayTone) : Color(.systemBackground))
    }
}

extension View {
    func themedBackground() -> some View { modifier(ThemedBackground()) }
    func themedBox(cornerRadius: CGFloat = 14) -> some View { modifier(ThemedBox(cornerRadius: cornerRadius)) }
    func themedPanel() -> some View { modifier(ThemedPanel()) }
}
