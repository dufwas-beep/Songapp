import SwiftData
import SwiftUI

/// "Passar efter": låtar som passar efter den som spelas, styrda av färgerna man väljer.
/// Låtar som spelats under kvällen visas aldrig här. Tryck = öppna i förhandsrutan.
struct SuggestionsBox: View {
    let current: Song?
    @Query private var songs: [Song]
    @Environment(Player.self) private var player
    @Environment(ColorCodes.self) private var codes
    /// Var förslagen hämtas: hela biblioteket eller bara låtlistan man spelar ur.
    @AppStorage("nextScope") private var scope = NextScope.library

    enum NextScope: String {
        case library, setlist
    }

    private var suggestions: [Song] {
        guard let current else { return [] }
        let colors = player.activeColors
        var available = songs.filter { $0.id != current.id && $0.kind != .note && !player.isPlayedTonight($0) }
        if scope == .setlist, let ids = player.setlistSongIDs {
            // Bara låtlistan, i listans ordning. Utan valda färger visas alla som är kvar.
            let order = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            available = available.filter { order[$0.id] != nil }.sorted { order[$0.id]! < order[$1.id]! }
            if colors.isEmpty {
                return player.pinned.compactMap { id in available.first { $0.id == id } }
                    + available.filter { !player.pinned.contains($0.id) }
            }
        }
        let pinned = player.pinned.compactMap { id in available.first { $0.id == id } }
        let matching = available
            .filter { !player.pinned.contains($0.id) && !colors.isDisjoint(with: $0.colorTags) }
            .sorted {
                let a = colors.intersection($0.colorTags).count
                let b = colors.intersection($1.colorTags).count
                return a != b ? a > b : Song.swedishOrder($0, $1)
            }
        // De 40 bästa räcker – färre rader gör rutan snabbare.
        return pinned + matching.prefix(40)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Samma färgrubriker som i låtlistan. Tryck på en rubrik för att välja om
            // färgen ska styra förslagen – valda färger är markerade.
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXT")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Menu {
                        Picker("Visa", selection: $scope) {
                            Label("Hela biblioteket", systemImage: "books.vertical").tag(NextScope.library)
                            Label("Bara låtlistan", systemImage: "list.bullet").tag(NextScope.setlist)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(scope == .library ? "Hela biblioteket" : "Bara låtlistan")
                            Image(systemName: "chevron.down")
                        }
                        .font(.caption.weight(.semibold))
                    }
                    Text(current == nil ? "Välj en låt" : (current?.colorTags.isEmpty == true ? "Låten har inga färger" : "Tryck på färgerna"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 4)
                Spacer()
                ForEach(current?.colorTags ?? [], id: \.self) { index in
                    let isOn = player.activeColors.contains(index)
                    VStack(spacing: 4) {
                        Text(codes.names[index])
                            .font(.system(size: 10, weight: isOn ? .bold : .medium))
                            .lineLimit(1)
                            .fixedSize()
                            .rotationEffect(.degrees(-90))
                            .frame(width: ColorDots.columnWidth, height: 58)
                        Capsule()
                            .fill(ColorCodes.colors[index])
                            .frame(width: 16, height: 3)
                    }
                    .background(isOn ? ColorCodes.colors[index].opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .opacity(isOn ? 1 : 0.4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isOn { player.activeColors.remove(index) } else { player.activeColors.insert(index) }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(codes.names[index])
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 20)
            .padding(.vertical, 8)
            Divider()
            let list = suggestions
            // Samma kolumner som rubrikerna ovanför.
            let columns = current?.colorTags ?? []
            List {
                ForEach(list) { song in
                    Button {
                        player.previewID = song.id
                    } label: {
                        HStack(spacing: 6) {
                            if player.pinned.contains(song.id) {
                                Image(systemName: "pin.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                            }
                            Text(song.title)
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            ColorDots(song: song, editable: false, columns: columns)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(player.lotteryHighlight == song.id ? Color.accentColor : (player.previewID == song.id ? Color.accentColor.opacity(0.25) : nil))
                    .contextMenu { PinButton(songID: song.id) }
                }
            }
            .listStyle(.plain)
            .overlay {
                if list.isEmpty, current != nil, !player.activeColors.isEmpty {
                    Text("Inga fler låtar med de färgerna ikväll.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .themedBox()
        // Lyckohjulet: markeringen hoppar mellan förslagen, saktar in och landar på en
        // slumpad låt som öppnas i förhandsrutan. Spelade låtar finns aldrig med.
        .onChange(of: player.lotteryRuns) {
            let list = suggestions
            guard !list.isEmpty else { return }
            let target = Int.random(in: 0..<list.count)
            // Ett kort snurr (ungefär en sekund) som slutar på den slumpade låten.
            let hops = 14
            Task {
                var delay = 0.03
                for hop in 0...hops {
                    let index = ((target - hops + hop) % list.count + list.count) % list.count
                    player.lotteryHighlight = list[index].id
                    try? await Task.sleep(for: .seconds(delay))
                    delay = min(delay * 1.15, 0.15)
                }
                player.previewID = list[target].id
                try? await Task.sleep(for: .seconds(0.4))
                player.lotteryHighlight = nil
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.2)))
    }
}

/// Fäst eller lossa en låt överst bland kvällens förslag.
struct PinButton: View {
    let songID: UUID
    @Environment(Player.self) private var player

    var body: some View {
        Button {
            player.togglePin(songID)
        } label: {
            if player.pinned.contains(songID) {
                Label("Ta bort från förslagen", systemImage: "pin.slash")
            } else {
                Label("Fäst bland förslagen", systemImage: "pin")
            }
        }
    }
}

/// Längst ner i sidospalten: "Ny spelning", hur många låtar som spelats ikväll och en
/// meny med kvällsloggar och säkerhetskopia.
struct GigFooter: View {
    @Query private var songs: [Song]
    @Environment(Player.self) private var player
    @State private var confirming = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                confirming = true
            } label: {
                Text("Ny spelning")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .controlSize(.large)
            let count = songs.filter(player.isPlayedTonight).count
            Text(count == 1 ? "1 spelad" : "\(count) spelade")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog("Starta en ny spelning?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Ny spelning") { player.newGig() }
        } message: {
            Text("Gråmarkeringar och fästa förslag nollställs, och en ny kvällslogg börjar.")
        }
    }
}
