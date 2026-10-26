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
        return pinned + matching
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("PASSAR EFTER – VÄLJ FÄRGER")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                if let current, !current.colorTags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(current.colorTags, id: \.self) { index in
                            let isOn = player.activeColors.contains(index)
                            Button {
                                if isOn { player.activeColors.remove(index) } else { player.activeColors.insert(index) }
                            } label: {
                                HStack(spacing: 5) {
                                    Circle().fill(ColorCodes.colors[index]).frame(width: 9, height: 9)
                                    Text(codes.names[index]).font(.caption.weight(.medium))
                                }
                                .padding(.horizontal, 9)
                                .frame(height: 26)
                                .background(isOn ? ColorCodes.colors[index].opacity(0.25) : .clear, in: Capsule())
                                .overlay(Capsule().stroke(isOn ? ColorCodes.colors[index] : Color.secondary.opacity(0.4), lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                } else {
                    Text(current == nil ? "Välj en låt för att få förslag." : "Låten har inga färgkoder än.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            Divider()
            let list = suggestions
            let columns = visibleColorColumns(list, colorMode: false)
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
