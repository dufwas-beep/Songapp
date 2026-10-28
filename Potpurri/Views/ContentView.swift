import SwiftData
import SwiftUI

/// Liggande: låtlistor/bibliotek till vänster och låten till höger.
/// Stående: låten i helskärm och sidospalten som en meny man drar fram.
struct ContentView: View {
    @Query private var songs: [Song]
    @Query private var setlists: [Setlist]
    @Environment(\.modelContext) private var context
    @State private var selection: Song?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var player = Player()
    @State private var colorCodes = ColorCodes()
    @State private var sounds = SoundEngine()
    @State private var spotify = SpotifyController()
    @State private var renameDraft = ""
    @State private var doveStart: Date?
    @AppStorage("migratedSongNotes") private var migratedSongNotes = false
    @AppStorage("appearance") private var appearance = Appearance.system
    @AppStorage("hasSeenGuide") private var hasSeenGuide = false
    @State private var showsGuide = false
    /// Sidospaltens bredd – dras i handtaget mellan spalten och låten.
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 380
    @State private var sidebarDrag: CGFloat?
    @State private var windowSize: CGSize = .zero
    @State private var order = LibraryOrder()
    /// Ökas när en låt byter namn, så att bokstavsordningen räknas om.
    @State private var titleVersion = 0

    /// Låtarna i bokstavsordning och uppslag på id. Räknas bara om när låtar läggs till,
    /// tas bort eller byter namn – inte vid varje låtbyte.
    final class LibraryOrder {
        var key: Int?
        var ids: [UUID] = []
        var byID: [UUID: Song] = [:]
    }

    private var currentOrder: LibraryOrder {
        var hasher = Hasher()
        hasher.combine(titleVersion)
        for song in songs { hasher.combine(ObjectIdentifier(song)) }
        let key = hasher.finalize()
        if order.key != key {
            let sorted = songs.sorted(by: Song.swedishOrder)
            order.ids = sorted.map(\.id)
            order.byID = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            order.key = key
        }
        return order
    }
    @Environment(\.scenePhase) private var scenePhase

    private func song(_ id: UUID?) -> Song? {
        guard let id else { return nil }
        return currentOrder.byID[id]
    }

    /// Nästa (+1) eller förra (−1) låt: i listan låten valdes ur, annars i biblioteket.
    private func neighbor(_ step: Int) -> Song? {
        // Ett förslag som spelas har ingen nästa låt – pedalen bläddrar bara inom det.
        guard let id = selection?.id, player.playingSuggestionID != id else { return nil }
        let order = player.queue.contains(id) ? player.queue : currentOrder.ids
        guard let index = order.firstIndex(of: id), order.indices.contains(index + step) else { return nil }
        return song(order[index + step])
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
                .themedBackground()
                .navigationSplitViewColumnWidth(CGFloat(sidebarWidth))
        } detail: {
            SongDetailView(
                song: selection,
                previous: neighbor(-1),
                next: neighbor(1),
                preview: song(player.previewID),
                onSelect: { song in
                    player.startSwitchTimer()
                    player.playingSuggestionID = nil
                    selection = song
                },
                onPlayPreview: { song in
                    // Låtlistan ändras inte när ett förslag spelas.
                    player.startSwitchTimer()
                    player.previewID = nil
                    player.playingSuggestionID = song.id
                    selection = song
                },
                sidebarHidden: columnVisibility == .detailOnly,
                onToggleSidebar: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                    }
                }
            )
            .themedBackground()
            .overlay(alignment: .bottomLeading) {
                SwitchTimerLabel().padding(24)
            }
            .overlay(alignment: .leading) {
                // Liggande: dra i handtaget vid kanten för att göra listorna bredare/smalare.
                if columnVisibility != .detailOnly && windowSize.width > windowSize.height {
                    SidebarResizeHandle(width: $sidebarWidth, drag: $sidebarDrag)
                }
            }
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            windowSize = size
        }
        .overlay {
            LaunchAnimation()
        }
        .overlay {
            if player.screensaverOn {
                ScreensaverView { player.screensaverOn = false }
                    .transition(.opacity)
            }
        }
        .overlay {
            if let doveStart {
                DoveFlight(start: doveStart)
                    .id(doveStart)
            }
        }
        .onChange(of: player.doveFlights) {
            let start = Date()
            doveStart = start
            Task {
                try? await Task.sleep(for: .seconds(DoveFlight.duration))
                if doveStart == start { doveStart = nil }
            }
        }
        // Låttexten i PDF:er och bilder läses ut i bakgrunden så att sökningen hittar den.
        .task(id: songs.count) {
            // Alla PDF:er ritas en gång till färdiga sidor, så att varje låt öppnas direkt.
            PDFPageRenderer.shared.prepare(songs.filter { $0.kind == .pdf }.map(\.fileURL))
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
            if id == nil { titleVersion += 1 }
            renameDraft = song(id)?.title ?? ""
        }
        .sheet(isPresented: Binding(get: { player.editingTextSongID != nil }, set: { if !$0 { player.editingTextSongID = nil } })) {
            if let found = song(player.editingTextSongID) {
                SongTextEditor(song: found)
            }
        }
        .sheet(isPresented: $showsGuide) {
            GuideView().themedBackground()
        }
        .preferredColorScheme(appearance.colorScheme)
        .environment(player)
        .environment(colorCodes)
        .environment(sounds)
        .environment(spotify)
        // Nästa dag (efter kl. 06) börjar en ny spelning av sig själv.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                player.startNewGigIfStale()
                runAutoBackup()
            }
        }
        .onChange(of: player.songsToDelete) { _, ids in
            guard !ids.isEmpty else { return }
            if ids.count == 1 {
                deleteSongs(ids)
            } else {
                Task {
                    // Testlåtarna: vänta tills inställningarna har stängts.
                    try? await Task.sleep(for: .milliseconds(400))
                    deleteSongs(ids)
                }
            }
        }
        .onChange(of: player.requestedSongID) { _, id in
            guard let id else { return }
            selection = song(id)
            player.requestedSongID = nil
        }
        .onChange(of: selection) { _, song in
            player.markSwitchSelected()
            // Har appen stått öppen över natten börjar en ny spelning vid första låten.
            player.startNewGigIfStale()
            player.selectedSongID = song?.id
            player.updateColors(for: song)
            if player.previewID == song?.id { player.previewID = nil }
        }
        .onAppear {
            // Skärmen släcks aldrig medan Potpurri är öppen.
            UIApplication.shared.isIdleTimerDisabled = true
            fixSongsImportedAsNotes()
            player.startNewGigIfStale()
            runAutoBackup()
            // Guiden visas första gången, efter startanimationen.
            if !hasSeenGuide {
                hasSeenGuide = true
                Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    showsGuide = true
                }
            }
        }
    }

    /// Veckans automatiska säkerhetskopia – en stund efter start så att appen hinner igång.
    private func runAutoBackup() {
        guard AutoBackup.isOn else { return }
        Task {
            try? await Task.sleep(for: .seconds(20))
            try? await AutoBackup.runIfDue(context: context, colorNames: colorCodes.names)
        }
    }

    /// Tar bort låtar ur biblioteket, låtlistorna och allt som visas just nu.
    private func deleteSongs(_ ids: Set<UUID>) {
        if let id = selection?.id, ids.contains(id) { selection = nil }
        if let id = player.previewID, ids.contains(id) { player.previewID = nil }
        if let id = player.playingSuggestionID, ids.contains(id) { player.playingSuggestionID = nil }
        if let id = player.drawerSongID, ids.contains(id) { player.drawerSongID = nil }
        player.queue.removeAll(where: ids.contains)
        player.pinned.removeAll(where: ids.contains)
        for list in setlists where list.songIDs.contains(where: ids.contains) {
            for id in list.songIDs where ids.contains(id) { list.removeSong(id) }
        }
        for song in songs where ids.contains(song.id) {
            SongFileStore.delete(song.fileName)
            context.delete(song)
        }
        try? context.save()
        player.songsToDelete = []
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

/// Handtaget mellan sidospalten och låten. En rosa linje visar den nya kanten medan
/// man drar; bredden ändras när man släpper (så att listorna inte ritas om hela tiden).
private struct SidebarResizeHandle: View {
    @Binding var width: Double
    @Binding var drag: CGFloat?
    static let range: ClosedRange<Double> = 300...640

    var body: some View {
        ZStack(alignment: .leading) {
            if let drag {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                    .offset(x: drag)
                    .allowsHitTesting(false)
            }
            Capsule()
                .fill(drag == nil ? Color.secondary.opacity(0.4) : Color.accentColor)
                .frame(width: 5, height: 48)
                .padding(.leading, 5)
                .frame(width: 26, height: 120, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .global)
                        .onChanged { value in
                            let target = min(max(width + value.translation.width, Self.range.lowerBound), Self.range.upperBound)
                            drag = CGFloat(target - width)
                        }
                        .onEnded { _ in
                            if let drag { width += Double(drag) }
                            drag = nil
                        }
                )
                .accessibilityLabel("Ändra bredden på listorna")
        }
    }
}

/// Liten klocka (TT:MM) när sidospalten är dold.
struct ClockLabel: View {
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

/// Tidtagaren (slås på under kugghjulet): hur lång tid det senaste låtbytet tog.
private struct SwitchTimerLabel: View {
    @Environment(Player.self) private var player
    @AppStorage("showsSwitchTimer") private var showsSwitchTimer = false

    var body: some View {
        if showsSwitchTimer, let report = player.lastSwitchReport {
            Text(report)
                .font(.footnote.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .allowsHitTesting(false)
        }
    }
}
