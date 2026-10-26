import SwiftData
import SwiftUI

/// Liggande: låtlistor/bibliotek till vänster och låten till höger.
/// Stående: låten i helskärm och sidospalten som en meny man drar fram.
struct ContentView: View {
    @Query private var songs: [Song]
    @State private var selection: Song?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var player = Player()
    @State private var colorCodes = ColorCodes()
    @State private var renameDraft = ""
    @AppStorage("migratedSongNotes") private var migratedSongNotes = false
    @Environment(\.scenePhase) private var scenePhase

    private func song(_ id: UUID?) -> Song? {
        guard let id else { return nil }
        return songs.first { $0.id == id }
    }

    /// Nästa (+1) eller förra (−1) låt: i listan låten valdes ur, annars i biblioteket.
    private func neighbor(_ step: Int) -> Song? {
        // Ett förslag som spelas har ingen nästa låt – pedalen bläddrar bara inom det.
        guard let id = selection?.id, player.playingSuggestionID != id else { return nil }
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
                preview: song(player.previewID),
                onSelect: { song in
                    player.playingSuggestionID = nil
                    selection = song
                },
                onPlayPreview: { song in
                    // Låtlistan ändras inte när ett förslag spelas.
                    player.previewID = nil
                    player.playingSuggestionID = song.id
                    selection = song
                }
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
        // Låttexten i PDF:er och bilder läses ut i bakgrunden så att sökningen hittar den.
        .task(id: songs.count) {
            await SearchIndexer.run(songs: songs, progress: player.indexing)
        }
        .alert("Byt namn på låten", isPresented: Binding(get: { player.renamingSongID != nil }, set: { if !$0 { player.renamingSongID = nil } })) {
            TextField("Namn", text: $renameDraft)
            Button("Avbryt", role: .cancel) {}
            Button("Spara") {
                let name = renameDraft.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, let found = song(player.renamingSongID) { found.title = name }
                player.renamingSongID = nil
            }
        }
        .onChange(of: player.renamingSongID) { _, id in
            renameDraft = song(id)?.title ?? ""
        }
        .sheet(isPresented: Binding(get: { player.editingTextSongID != nil }, set: { if !$0 { player.editingTextSongID = nil } })) {
            if let found = song(player.editingTextSongID) {
                SongTextEditor(song: found)
            }
        }
        .environment(player)
        .environment(colorCodes)
        // Efter 12 timmar börjar en ny spelning av sig själv (t.ex. nästa dag).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { player.startNewGigIfStale() }
        }
        .onChange(of: selection) { _, song in
            player.updateColors(for: song)
            if player.previewID == song?.id { player.previewID = nil }
        }
        .onAppear {
            // Skärmen släcks aldrig medan Potpurri är öppen.
            UIApplication.shared.isIdleTimerDisabled = true
            fixSongsImportedAsNotes()
            player.startNewGigIfStale()
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
        HStack(spacing: 8) {
            TimelineView(.everyMinute) { context in
                Text(context.date, format: Date.FormatStyle(locale: Locale(identifier: "sv_SE")).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
            }
            SetTimerButton()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
    }
}
