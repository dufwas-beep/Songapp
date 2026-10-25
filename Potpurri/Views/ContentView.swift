import SwiftData
import SwiftUI

/// Liggande: låtlistor/bibliotek till vänster och låten till höger.
/// Stående: låten i helskärm och sidospalten som en meny man drar fram.
struct ContentView: View {
    @Query private var songs: [Song]
    @State private var selection: Song?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var player = Player()
    @AppStorage("migratedSongNotes") private var migratedSongNotes = false

    private func song(_ id: UUID?) -> Song? {
        guard let id else { return nil }
        return songs.first { $0.id == id }
    }

    /// Nästa (+1) eller förra (−1) låt: i listan låten valdes ur, annars i biblioteket.
    private func neighbor(_ step: Int) -> Song? {
        guard let id = selection?.id else { return nil }
        let order = player.queue.contains(id) ? player.queue : songs.sorted(by: Song.swedishOrder).map(\.id)
        guard let index = order.firstIndex(of: id), order.indices.contains(index + step) else { return nil }
        return song(order[index + step])
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
        } detail: {
            SongDetailView(
                song: selection,
                previous: neighbor(-1),
                next: neighbor(1),
                onSelect: { selection = $0 }
            )
            .overlay(alignment: .topLeading) {
                // När sidospalten är dold visas klockan i låtvyn i stället.
                if columnVisibility == .detailOnly {
                    ClockLabel()
                        .padding(.leading, 70)
                        .padding(.top, 6)
                }
            }
        }
        .environment(player)
        .onAppear {
            // Skärmen släcks aldrig medan Potpurri är öppen.
            UIApplication.shared.isIdleTimerDisabled = true
            fixSongsImportedAsNotes()
        }
    }

    /// Tidigare blev OnSong-låtar utan ackord felaktigt anteckningar. Bara quizmanus
    /// ska vara anteckningar; övriga görs om till låtar (en gång).
    private func fixSongsImportedAsNotes() {
        guard !migratedSongNotes else { return }
        for song in songs where song.kind == .note && !NoteText.looksLikeQuiz(song.text ?? "") {
            song.kindRaw = SongKind.text.rawValue
        }
        migratedSongNotes = true
    }
}

/// Liten klocka (TT:MM) när sidospalten är dold.
private struct ClockLabel: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date, format: Date.FormatStyle(locale: Locale(identifier: "sv_SE")).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
        }
    }
}
