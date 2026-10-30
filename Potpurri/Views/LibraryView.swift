import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Hur biblioteket sorteras.
enum LibrarySort: String, CaseIterable {
    case name
    case added
    case lastPlayed
    case mostPlayed

    var label: String {
        switch self {
        case .name: return "Namn"
        case .added: return "Senast tillagd"
        case .lastPlayed: return "Senast spelad"
        case .mostPlayed: return "Mest spelad"
        }
    }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(Player.self) private var player
    @Environment(ColorCodes.self) private var codes
    @Query private var allSongs: [Song]
    /// Quiz-fliken: bara låtar som heter något med "Quiz" eller "HLS".
    var quizOnly = false

    @AppStorage(Feature.quiz.key) private var quizTabOn = true

    /// Låtarna fliken visar: quizen i Quiz-fliken, allt annat i biblioteket.
    /// (Är Quiz-fliken avstängd ligger quizen kvar i biblioteket.)
    /// Sparas tills en titel ändras eller låtar läggs till – urvalet jämför text i varje
    /// titel och gjordes förut om för varje rad i listan, vilket frös appen i flera sekunder.
    private var songs: [Song] {
        var hasher = Hasher()
        hasher.combine(quizOnly)
        hasher.combine(quizTabOn)
        for song in allSongs {
            hasher.combine(song.id)
            hasher.combine(song.title)
        }
        let key = hasher.finalize()
        if cache.songsKey == key { return cache.songs }
        let result: [Song]
        if quizOnly {
            result = allSongs.filter(Self.isQuiz)
        } else {
            result = quizTabOn ? allSongs.filter { !Self.isQuiz($0) } : allSongs
        }
        cache.songsKey = key
        cache.songs = result
        return result
    }

    static func isQuiz(_ song: Song) -> Bool {
        isQuizTitle(song.title)
    }

    static func isQuizTitle(_ title: String) -> Bool {
        title.range(of: "quiz", options: [.caseInsensitive, .diacriticInsensitive]) != nil
            || title.range(of: "hls", options: .caseInsensitive) != nil
    }

    @AppStorage("sidebarTab") private var sidebarTab = SidebarView.SidebarTab.setlists
    @Query private var setlists: [Setlist]

    @AppStorage("librarySort") private var sort = LibrarySort.name
    /// Det som står i sökrutan, och sökningen som används (en kort stund efter sista
    /// tangenttrycket, så att skrivandet aldrig hackar).
    @State private var typedQuery = ""
    @State private var query = ""
    @State private var showImporter = false
    @State private var importsOnSong = false
    @State private var onSongBackup: OnSongBackup?
    @State private var importMessage: String?
    @State private var progress = TaskProgress()
    @State private var colorMode = false
    @State private var checked: Set<UUID> = []
    @State private var colorFilter: Set<Int> = []
    /// Den sorterade listan sparas tills något som påverkar den ändras – svensk sortering
    /// av hundratals låtar är för långsam att göra om vid varje tryck (t.ex. i färgläget).
    @State private var cache = ListCache()
    @State private var webQuery: String?
    @State private var showsNewSong = false
    @State private var sharing: Set<UUID>?
    /// Quiz-fliken: quiz vars låtar visas under raden.
    @State private var expandedQuizzes: Set<UUID> = []

    final class ListCache {
        var songsKey: Int?
        var songs: [Song] = []
        var key: Int?
        var list: [Song] = []
        var letters: Set<String> = []
    }

    private var cacheKey: Int {
        var hasher = Hasher()
        hasher.combine(query)
        hasher.combine(sort)
        hasher.combine(colorFilter.sorted())
        for song in songs {
            hasher.combine(song.id)
            hasher.combine(song.title)
            if sort == .lastPlayed { hasher.combine(song.lastPlayed) }
            if sort == .mostPlayed { hasher.combine(song.playCount) }
            if !colorFilter.isEmpty { hasher.combine(song.colorTags) }
            if !query.isEmpty { hasher.combine(song.searchText == nil) }
        }
        return hasher.finalize()
    }

    private var cachedSongs: [Song] {
        let key = cacheKey
        if cache.key != key {
            cache.list = visibleSongs
            cache.letters = Set(songs.map(\.indexLetter))
            cache.key = key
        }
        return cache.list
    }

    /// Sökning på titel, färgfilter och vald sortering.
    private var visibleSongs: [Song] {
        let q = query.trimmingCharacters(in: .whitespaces)
        // Sökningen träffar både titel och låttext (även utläst ur PDF:er och bilder).
        // Korta sökningar (1–2 tecken) gäller bara titeln, annars träffar allt.
        var filtered = q.isEmpty ? songs : songs.filter { q.count < 3 ? $0.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil : $0.matches(q) }
        if !colorFilter.isEmpty {
            filtered = filtered.filter { !colorFilter.isDisjoint(with: $0.colorTags) }
        }
        let sorted: [Song]
        switch sort {
        case .name:
            sorted = filtered.sorted(by: Song.swedishOrder)
        case .added:
            sorted = filtered.sorted { $0.dateAdded > $1.dateAdded }
        case .lastPlayed:
            sorted = filtered.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        case .mostPlayed:
            sorted = filtered.sorted { $0.playCount != $1.playCount ? $0.playCount > $1.playCount : Song.swedishOrder($0, $1) }
        }
        if !q.isEmpty {
            // Bäst träff först: titeln börjar med sökningen, sedan ett ord i titeln,
            // sedan någonstans i titeln och sist bara i låttexten.
            let rank = { (song: Song) -> Int in
                let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .anchored]
                if song.title.range(of: q, options: options) != nil { return 0 }
                if song.title.split(separator: " ").contains(where: { String($0).range(of: q, options: options) != nil }) { return 1 }
                if song.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil { return 2 }
                return 3
            }
            return sorted.enumerated()
                .sorted { rank($0.element) != rank($1.element) ? rank($0.element) < rank($1.element) : $0.offset < $1.offset }
                .map(\.element)
        }
        guard !colorFilter.isEmpty else { return sorted }
        // Låtar med flest av de valda färgerna först, i övrigt vald sortering.
        let overlap = { (song: Song) in colorFilter.intersection(song.colorTags).count }
        return sorted.enumerated()
            .sorted { overlap($0.element) != overlap($1.element) ? overlap($0.element) > overlap($1.element) : $0.offset < $1.offset }
            .map(\.element)
    }

    private var showsAlphabet: Bool {
        // Inte i Quiz-fliken (där är det för få för att behövas).
        !quizOnly && sort == .name && query.isEmpty && colorFilter.isEmpty && !colorMode && songs.count > 20
    }

    /// Avstånd till högerkanten för raderna och färgrubrikerna (plats för alfabetet).
    private var rowTrailing: CGFloat {
        showsAlphabet ? 28 : 16
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SearchField(text: $typedQuery, prompt: "Sök titel eller låttext")
                sortMenu
                importMenu
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            let columns = visibleColorColumns(songs, colorMode: colorMode, count: codes.count)
            let list = cachedSongs
            // Räknas en gång här, inte för varje rad.
            let trailing = rowTrailing
            let sortedSetlists = setlists.sorted { Song.compareTitles($0.name, $1.name) }
            ColorColumnsHeader(colorMode: $colorMode, columns: columns, trailing: trailing, filter: $colorFilter) { index in
                applyColor(index, to: list.filter { checked.contains($0.id) })
            }
            .padding(.top, 4)
            .onChange(of: colorMode) { _, on in
                if !on { checked = [] }
            }
            if !colorFilter.isEmpty {
                CategoryFilterBar(filter: colorFilter, shown: list.count, total: songs.count) {
                    withAnimation { colorFilter = [] }
                }
            }
            if colorMode {
                CheckedActionsBar(
                    checkedCount: checked.count,
                    totalCount: list.count,
                    onSelectAll: { checked = Set(list.map(\.id)) },
                    onSelectNone: { checked = [] },
                    onCategory: { index in applyColor(index, to: list.filter { checked.contains($0.id) }) },
                    onAddToSetlist: { setlist in
                        // I listans ordning, som de syns i biblioteket.
                        setlist.songIDs.append(contentsOf: list.map(\.id).filter(checked.contains))
                        try? context.save()
                    },
                    deleteTitle: "Ta bort",
                    onDelete: {
                        player.songsToDelete = checked
                        checked = []
                    },
                    onShare: { sharing = checked }
                )
            }
            Divider()
            ScrollViewReader { proxy in
                // Egen lista (som i låtlistorna) i stället för iPadens: den inbyggda listan
                // räknade om alla rader vid varje låtbyte, vilket tog nästan en sekund.
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(list) { song in
                            libraryRow(song, in: list, columns: columns, trailing: trailing, setlists: sortedSetlists)
                                .id(song.id)
                            if quizOnly && expandedQuizzes.contains(song.id) {
                                QuizSongsList(quiz: song) { child in
                                    player.startSwitchTimer()
                                    player.requestedSongID = child.id
                                }
                                .padding(.leading, 40)
                                .padding(.trailing, 16)
                                .background(Color.accentColor.opacity(0.06))
                            }
                        }
                        // Hittar man inte låten: sök på webben.
                        if !query.trimmingCharacters(in: .whitespaces).isEmpty && !player.isLocked {
                            Button {
                                webQuery = query
                            } label: {
                                Label("Hittar du inte låten? Sök \"\(query)\" på webben", systemImage: "globe")
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                            }
                        }
                        Color.clear.frame(height: 40)
                    }
                }
                // En nyss importerad låt: scrolla fram till den (när listan hunnit få den).
                .onChange(of: player.revealSongID) { _, id in reveal(id, proxy: proxy) }
                .onAppear { reveal(player.revealSongID, proxy: proxy) }
                // Nästa/förra låt följer biblioteket när man valt en låt här.
                .overlay(alignment: .trailing) {
                    if showsAlphabet {
                        AlphabetScrubber(available: cache.letters) { letter in
                            if let first = list.first(where: { $0.indexLetter == letter }) {
                                proxy.scrollTo(first.id, anchor: .top)
                            }
                        }
                        .padding(.trailing, 2)
                    }
                }
            }
            .overlay {
                if songs.isEmpty && quizOnly {
                    ContentUnavailableView(
                        "Inga quiz ännu",
                        systemImage: "questionmark.bubble",
                        description: Text("Låtar och anteckningar som heter något med \"Quiz\" eller \"HLS\" visas här.")
                    )
                } else if songs.isEmpty {
                    ContentUnavailableView(
                        "Inga låtar ännu",
                        systemImage: "music.note.list",
                        description: Text("Tryck på + för att importera PDF:er och bilder från Filer, eller en OnSong-backup.")
                    )
                } else if list.isEmpty {
                    ContentUnavailableView {
                        Label("Ingen träff på \"\(query)\"", systemImage: "magnifyingglass")
                    } actions: {
                        Button("Sök på webben") { webQuery = query }
                            .buttonStyle(.borderedProminent)
                            .foregroundStyle(.black)
                            .disabled(player.isLocked)
                    }
                }
            }
        }
        .task(id: typedQuery) {
            let typed = typedQuery
            if !typed.isEmpty {
                try? await Task.sleep(for: .milliseconds(typed.count < 3 ? 120 : 300))
                guard !Task.isCancelled else { return }
            }
            query = typed
        }
        .shareSongs($sharing)
        .safeAreaInset(edge: .bottom) {
            if progress.isRunning {
                ProgressBanner(progress: progress)
            } else if player.indexing.isRunning {
                ProgressBanner(progress: player.indexing)
            }
        }
        // Helskärm – låttextsidorna är fulla av reklam och behöver plats.
        .fullScreenCover(isPresented: Binding(get: { webQuery != nil }, set: { if !$0 { webQuery = nil } })) {
            WebSearchSheet(initialQuery: webQuery ?? "") { song in
                typedQuery = ""
                query = ""
                player.requestedSongID = song.id
            }
        }
        .sheet(isPresented: $showsNewSong) {
            NewSongSheet { song in
                typedQuery = ""
                query = ""
                player.requestedSongID = song.id
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importsOnSong ? [.data] : SongImporter.allowedTypes,
            allowsMultipleSelection: !importsOnSong
        ) { result in
            switch result {
            case .success(let urls):
                if importsOnSong, let url = urls.first {
                    readOnSong(url)
                } else {
                    Task {
                        let result = await SongImporter.importFiles(urls, into: context, progress: progress)
                        showImported(result)
                    }
                }
            case .failure(let error):
                importMessage = "Importen misslyckades: \(error.localizedDescription)"
            }
        }
        .sheet(item: $onSongBackup) { backup in
            OnSongImportSheet(backup: backup) { selectedIDs in
                onSongBackup = nil
                Task {
                    importMessage = await OnSongImporter.importSongs(selectedIDs, from: backup, existing: allSongs, into: context, progress: progress)
                }
            } onCancel: {
                onSongBackup = nil
                backup.cleanUp()
            }
        }
        .alert(
            "Import",
            isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sortera", selection: $sort) {
                ForEach(LibrarySort.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .frame(width: 40, height: 40)
        }
        .accessibilityLabel("Sortera")
    }

    private var importMenu: some View {
        Menu {
            Button {
                showsNewSong = true
            } label: {
                Label("Ny låt (skriv eller klistra in)", systemImage: "square.and.pencil")
            }
            Divider()
            Button {
                importsOnSong = false
                showImporter = true
            } label: {
                Label("PDF:er, bilder och textfiler", systemImage: "doc.text")
            }
            Button {
                importsOnSong = true
                showImporter = true
            } label: {
                Label("OnSong-backup", systemImage: "archivebox")
            }
        } label: {
            Image(systemName: "plus")
                .font(.title3)
                .frame(width: 40, height: 40)
        }
        .disabled(progress.isRunning || player.isLocked)
        .guideSpot(.addSong)
        .accessibilityLabel("Importera")
    }

    @ViewBuilder
    private func rowMenu(for song: Song, setlists: [Setlist]) -> some View {
        Button {
            player.renamingSongID = song.id
        } label: {
            Label("Byt namn", systemImage: "pencil")
        }
        Menu {
            AddToSetlistItems(songID: song.id, setlists: setlists)
        } label: {
            Label("Lägg till i låtlista", systemImage: "text.badge.plus")
        }
        .disabled(setlists.isEmpty)
        Button(role: .destructive) {
            delete(song)
        } label: {
            Label("Ta bort", systemImage: "trash")
        }
    }

    /// Efter importen: den (sista) nya låten öppnas och syns i listan – quiz och HLS i
    /// Quiz-fliken, allt annat i biblioteket. Meddelande bara om något gick fel eller
    /// om flera filer importerades.
    private func showImported(_ result: ImportResult) {
        if !result.failed.isEmpty || result.imported > 1 {
            importMessage = result.summary
        }
        guard let last = result.added.last else { return }
        typedQuery = ""
        query = ""
        colorFilter = []
        sidebarTab = quizTabOn && Self.isQuizTitle(last.title) ? .quiz : .library
        player.startSwitchTimer()
        player.setlistSongIDs = nil
        player.requestedSongID = last.id
        player.revealSongID = last.id
    }

    private func reveal(_ id: UUID?, proxy: ScrollViewProxy) {
        guard let id else { return }
        Task {
            // Listan får den nya låten först när den ritats om – försök några gånger.
            for _ in 0..<5 {
                try? await Task.sleep(for: .milliseconds(300))
                guard player.revealSongID == id else { return }
                if cache.list.contains(where: { $0.id == id }) {
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                    player.revealSongID = nil
                    return
                }
            }
        }
    }

    private func readOnSong(_ url: URL) {
        let titles = Set(allSongs.map { $0.title.lowercased() })
        Task {
            do {
                let backup = try await OnSongImporter.read(url, existingTitles: titles, progress: progress)
                if backup.candidates.isEmpty {
                    backup.cleanUp()
                    importMessage = "Hittade inga låtar i backupen."
                } else {
                    onSongBackup = backup
                }
            } catch {
                importMessage = "OnSong-backupen kunde inte läsas: \(error.localizedDescription)"
            }
        }
    }

    /// En rad i biblioteket. Svep åt höger = Lådan, åt vänster = ta bort.
    private func libraryRow(_ song: Song, in list: [Song], columns: [Int], trailing: CGFloat, setlists: [Setlist]) -> some View {
        HStack(spacing: 8) {
            if colorMode {
                ColorModeCheckbox(isChecked: checked.contains(song.id)) {
                    if checked.contains(song.id) { checked.remove(song.id) } else { checked.insert(song.id) }
                }
            }
            SongRow(song: song, isPlayed: player.isPlayedTonight(song))
            if quizOnly {
                // Quizets låtar: tryck för att visa eller dölja dem under raden.
                let expanded = expandedQuizzes.contains(song.id)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if expanded { expandedQuizzes.remove(song.id) } else { expandedQuizzes.insert(song.id) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note.list")
                        Text("\(song.quizSongIDs.count)")
                            .monospacedDigit()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.footnote)
                    .foregroundStyle(expanded ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Dölj låtarna i quizet" : "Visa låtarna i quizet")
            }
            ColorDots(song: song, editable: colorMode, columns: columns)
        }
        .padding(.leading, 16)
        .padding(.trailing, trailing)
        .frame(minHeight: 44)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { open(song, in: list) }
        .background(SelectedRowBackground(songID: song.id))
        .modifier(SwipeRow(
            canDelete: !player.isLocked,
            onDelete: { delete(song) },
            onFullSwipeRight: { putInDrawer(song) },
            leading: { close in
                SwipeButton(title: "Lådan", systemImage: "tray.and.arrow.down", color: .accentColor) {
                    close()
                    putInDrawer(song)
                }
            }
        ))
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 16)
        }
        .draggable("song:\(song.id.uuidString)")
        .contextMenu {
            Button {
                putInDrawer(song)
            } label: {
                Label("Lägg i lådan", systemImage: "tray.and.arrow.down")
            }
            PinButton(songID: song.id)
            Button {
                sharing = [song.id]
            } label: {
                Label("Dela (AirDrop …)", systemImage: "square.and.arrow.up")
            }
            if !player.isLocked { rowMenu(for: song, setlists: setlists) }
        }
    }

    private func putInDrawer(_ song: Song) {
        player.drawerSongID = song.id
        withAnimation(.spring(response: 0.55, dampingFraction: 1)) { player.drawerOpen = true }
    }

    /// Öppnar en låt. Nästa/förra låt följer sedan biblioteket.
    private func open(_ song: Song, in list: [Song]) {
        player.startSwitchTimer()
        let ids = list.map(\.id)
        if player.queue != ids { player.queue = ids }
        player.setlistSongIDs = nil
        player.requestedSongID = song.id
    }

    /// Tar bort låten ur biblioteket och ur alla låtlistor.
    private func delete(_ song: Song) {
        // ContentView släpper låten ur alla vyer och listor och tar sedan bort den.
        player.songsToDelete = [song.id]
    }
}

struct SongRow: View {
    let song: Song
    /// Spelad under kvällen – visas grå men kan fortfarande väljas.
    var isPlayed = false

    var body: some View {
        HStack(spacing: 10) {
            Text(song.title)
                .lineLimit(1)
                .foregroundStyle(isPlayed ? .secondary : .primary)
            // Bara anteckningar (t.ex. quizmanus) märks – om en låt är PDF eller bild spelar ingen roll.
            if song.kind == .note {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Anteckning")
            }
            Spacer(minLength: 0)
            if isPlayed {
                Text("spelad")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let key = song.displayKey {
                Text(key)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Markeringen bakom den låt som visas. Egen vy så att bara den här raden ritas om
/// när man byter låt – inte hela biblioteket.
private struct SelectedRowBackground: View {
    let songID: UUID
    @Environment(Player.self) private var player

    var body: some View {
        if player.selectedSongID == songID {
            Color.accentColor.opacity(0.3)
        } else {
            Color.clear
        }
    }
}

/// Låtlistorna i menyn "Lägg till i låtlista". Egen vy så att listornas innehåll bara
/// läses när menyn öppnas – inte för varje rad när biblioteket ritas.
private struct AddToSetlistItems: View {
    let songID: UUID
    let setlists: [Setlist]
    @Environment(\.modelContext) private var context

    var body: some View {
        ForEach(setlists) { list in
            Button {
                list.songIDs.append(songID)
                try? context.save()
            } label: {
                // Bock = låten finns redan i listan (går ändå att lägga till igen).
                if list.songIDs.contains(songID) {
                    Label(list.name + " (finns redan)", systemImage: "checkmark")
                } else {
                    Text(list.name)
                }
            }
        }
    }
}
