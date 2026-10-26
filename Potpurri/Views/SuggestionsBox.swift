import SwiftData
import SwiftUI

/// "Passar efter": låtar som passar efter den som spelas, styrda av färgerna man väljer.
/// Låtar som spelats under kvällen visas aldrig här. Tryck = öppna i förhandsrutan.
struct SuggestionsBox: View {
    let current: Song?
    @Query private var songs: [Song]
    @Environment(Player.self) private var player
    @Environment(ColorCodes.self) private var codes

    private var suggestions: [Song] {
        guard let current else { return [] }
        let colors = player.activeColors
        let available = songs.filter { $0.id != current.id && $0.kind != .note && !player.isPlayedTonight($0) }
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
                    Text("PASSAR EFTER")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
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
                    .listRowBackground(player.previewID == song.id ? Color.accentColor.opacity(0.25) : nil)
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
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
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

/// Längst ner i sidospalten: "Ny spelning" och hur många låtar som spelats ikväll.
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
            Text("Gråmarkeringar och fästa förslag nollställs.")
        }
    }
}
