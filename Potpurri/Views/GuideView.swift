import SwiftUI

/// Guiden börjar med ett val: Snabbintro (det som är unikt för Potpurri) eller Hela
/// guiden. Sedan visas rundturen ovanpå appen (`GuideTour`) och pekar på rätt ställen.
struct GuideChooser: View {
    let onChoose: ([GuidePage]) -> Void
    @Environment(\.dismiss) private var dismiss

    static let shortPages: [GuidePage] = [
        GuidePage(symbol: "logo", title: "Det här gör Potpurri unikt",
                  text: "Sex saker som gör scenen enklare. Guiden visar var de finns – en minut, sedan kör vi."),
        GuidePage(symbol: "sparkles", title: "Next",
                  text: "Här föreslås låtar som passar efter den du spelar, styrt av kategorierna. Tryck på ett förslag för att titta i förhandsrutan – tryck på loggan för en slumpad låt.",
                  spot: .next),
        GuidePage(symbol: "arrow.down.to.line", title: "Hopplinjer",
                  text: "Under ⋯ → Hopplinjer lägger du linjer i låten. Ett tryck i låten eller på pedalen hoppar till nästa linje – perfekt för repriser.",
                  spot: .songMenu),
        GuidePage(symbol: "speaker.wave.2", title: "Soundboard",
                  text: "Högtalaren öppnar egna ljudklipp i högerkanten – applåder, jinglar, intron. Ett tryck spelar, ett till stoppar.",
                  spot: .soundboard),
        GuidePage(symbol: "music.note", title: "Ackord",
                  text: "Under ⋯ → Ackord lägger du ackord ovanpå vilken låt som helst, även PDF:er. Transponera hela låten med ♭ och ♯.",
                  spot: .songMenu),
        GuidePage(symbol: "tag", title: "Kategorier",
                  text: "Märk låtar med upp till sju kategorier, t.ex. Allsång, Lugn och Dans. Tryck på en kategori ovanför listan för att bara se de låtarna.",
                  spot: .categories, tab: .library),
        GuidePage(symbol: "tray", title: "Lådan",
                  text: "Dra i handtaget eller svep en låt åt höger i listan – då hamnar den i Lådan, med ett gult fält för egna anteckningar.",
                  spot: .drawer),
    ]

    static let fullPages: [GuidePage] = [
        GuidePage(symbol: "logo", title: "Välkommen till Potpurri",
                  text: "Alla dina låtar på ett ställe – PDF:er, bilder och textlåtar med ackord. Här är en rundtur."),
        GuidePage(symbol: "square.and.arrow.down", title: "Lägg in låtar",
                  text: "Plus hämtar PDF:er och bilder från Filer, läser in ett OnSong-bibliotek eller låter dig skriva en ny låt. Sök hittar även texten inne i låtarna.",
                  spot: .addSong, tab: .library),
        GuidePage(symbol: "list.bullet.rectangle", title: "Låtlistor, bibliotek och quiz",
                  text: "Växla mellan låtlistorna, hela biblioteket och quizen. I en låtlista håller du in en låt och drar för att ändra ordning.",
                  spot: .tabs, tab: .setlists),
        GuidePage(symbol: "lock", title: "Loggan",
                  text: "Tryck = slumpad låt bland förslagen. Håll in = scenlås, så att inget ändras av misstag. Dubbeltryck – prova!",
                  spot: .logo),
        GuidePage(symbol: "hand.tap", title: "Spela",
                  text: "Tryck i låten eller använd pedalen för att gå vidare. Här byter du till förra och nästa låt.",
                  spot: .stepButtons),
        GuidePage(symbol: "pencil.tip.crop.circle", title: "Penna, notes, hopplinjer och ackord",
                  text: "Under ⋯ finns markeringspenna, notes, hopplinjer, ackord, kategorier och autoscroll.",
                  spot: .songMenu),
        GuidePage(symbol: "sparkles", title: "Next",
                  text: "Förslag på nästa låt, styrda av kategorierna. Spelade låtar blir gråa och en ny spelning börjar av sig själv nästa dag.",
                  spot: .next),
        GuidePage(symbol: "tag", title: "Kategorier",
                  text: "Tryck på Markera för att kryssa i flera låtar på en gång – ge dem en kategori, lägg dem i en låtlista eller ta bort dem. Tryck på en kategorirubrik för att bara se de låtarna.",
                  spot: .categories, tab: .library),
        GuidePage(symbol: "tray", title: "Lådan",
                  text: "Handtaget i högerkanten drar ut Lådan – en låt eller anteckning med ett gult fält för egna anteckningar.",
                  spot: .drawer),
        GuidePage(symbol: "speaker.wave.2", title: "Soundboard",
                  text: "Egna ljudklipp i högerkanten. Ett tryck spelar, ett till stoppar.",
                  spot: .soundboard),
        GuidePage(symbol: "play.circle", title: "Spotify",
                  text: "Spela, pausa och byt låt i Spotify mellan numren. Håll in för att logga in.",
                  spot: .spotify),
        GuidePage(symbol: "cup.and.saucer", title: "Paus",
                  text: "Koppen startar skärmsläckaren i pauserna. Tryck på skärmen för att fortsätta.",
                  spot: .pause),
        GuidePage(symbol: "lightbulb", title: "Idélådan",
                  text: "Skriv upp låtförslag, saker att köpa, något att testa eller förbättringar för appen. Allt sorteras automatiskt.",
                  spot: .ideas),
        GuidePage(symbol: "gearshape", title: "Inställningar",
                  text: "Kvällsloggar, säkerhetskopia, utseende och den här guiden igen.",
                  spot: .settings),
    ]

    var body: some View {
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
            Text("Guiden visar direkt på skärmen var allt finns.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 12) {
                Button {
                    onChoose(Self.shortPages)
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
                    onChoose(Self.fullPages)
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
