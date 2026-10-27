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
    @Query private var songs: [Song]
    @Query private var setlists: [Setlist]
    @Binding var selection: Song?

    @AppStorage("librarySort") private var sort = LibrarySort.name
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

    final class ListCache {
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
            if !query.isEmpty { hasher.combine(song.searchText?.count) }
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
        sort == .name && query.isEmpty && colorFilter.isEmpty && !colorMode && songs.count > 20
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SearchField(text: $query, prompt: "Sök titel eller låttext")
                sortMenu
                importMenu
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            let columns = visibleColorColumns(songs, colorMode: colorMode)
            if !columns.isEmpty && !colorMode {
                ColorFilterChips(selected: $colorFilter, columns: columns)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            let list = cachedSongs
            ColorColumnsHeader(colorMode: $colorMode, columns: columns) { index in
                applyColor(index, to: list.filter { checked.contains($0.id) })
            }
            .onChange(of: colorMode) { _, on in
                if !on { checked = [] }
            }
            Divider()
            ScrollViewReader { proxy in
                List(selection: $selection) {
                    ForEach(list) { song in
                        HStack(spacing: 8) {
                            if colorMode {
                                ColorModeCheckbox(isChecked: checked.contains(song.id)) {
                                    if checked.contains(song.id) { checked.remove(song.id) } else { checked.insert(song.id) }
                                }
                            }
                            SongRow(song: song, isPlayed: player.isPlayedTonight(song))
                            ColorDots(song: song, editable: colorMode, columns: columns)
                        }
                            .tag(song)
                            .id(song.id)
                            .padding(.trailing, showsAlphabet ? 18 : 0)
                            .draggable("song:\(song.id.uuidString)")
                            // Svep åt höger = lägg i Lådan.
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    player.drawerSongID = song.id
                                    withAnimation(.spring(response: 0.55, dampingFraction: 1)) { player.drawerOpen = true }
                                } label: {
                                    Label("Lådan", systemImage: "tray.and.arrow.down")
                                }
                                .tint(.accentColor)
                            }
                            .contextMenu {
                                Button {
                                    player.drawerSongID = song.id
                                    withAnimation(.spring(response: 0.55, dampingFraction: 1)) { player.drawerOpen = true }
                                } label: {
                                    Label("Lägg i lådan", systemImage: "tray.and.arrow.down")
                                }
                                PinButton(songID: song.id)
                                if !player.isLocked { rowMenu(for: song) }
                            }
                    }
                    .onDelete(perform: deleteAction(in: list))
                    // Hittar man inte låten: sök på webben.
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty && !player.isLocked {
                        Button {
                            webQuery = query
                        } label: {
                            Label("Hittar du inte låten? Sök \"\(query)\" på webben", systemImage: "globe")
                                .font(.subheadline)
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                // Nästa/förra låt följer biblioteket när man valt en låt här.
                .onChange(of: selection) { _, song in
                    if let song, song.id != player.playingSuggestionID, list.contains(song) {
                        player.queue = list.map(\.id)
                    }
                }
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
                if songs.isEmpty {
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
        .safeAreaInset(edge: .bottom) {
            if progress.isRunning {
                ProgressBanner(progress: progress)
            } else if player.indexing.isRunning {
                ProgressBanner(progress: player.indexing)
            }
        }
        .sheet(isPresented: Binding(get: { webQuery != nil }, set: { if !$0 { webQuery = nil } })) {
            WebSearchSheet(initialQuery: webQuery ?? "") { song in
                query = ""
                selection = song
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
                        importMessage = await SongImporter.importFiles(urls, into: context, progress: progress).summary
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
                    importMessage = await OnSongImporter.importSongs(selectedIDs, from: backup, existing: songs, into: context, progress: progress)
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
        .accessibilityLabel("Importera")
    }

    @ViewBuilder
    private func rowMenu(for song: Song) -> some View {
        Button {
            player.renamingSongID = song.id
        } label: {
            Label("Byt namn", systemImage: "pencil")
        }
        Menu {
            ForEach(setlists.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { list in
                Button(list.name) {
                    list.songIDs.append(song.id)
                    try? context.save()
                }
            }
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

    private func readOnSong(_ url: URL) {
        let titles = Set(songs.map { $0.title.lowercased() })
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

    /// Svep för att ta bort – av när scenlåset är på.
    private func deleteAction(in list: [Song]) -> ((IndexSet) -> Void)? {
        guard !player.isLocked else { return nil }
        return { offsets in
            offsets.map { list[$0] }.forEach(delete)
        }
    }

    /// Tar bort låten ur biblioteket och ur alla låtlistor.
    private func delete(_ song: Song) {
        if selection == song { selection = nil }
        for list in setlists where list.songIDs.contains(song.id) {
            list.removeSong(song.id)
        }
        SongFileStore.delete(song.fileName)
        context.delete(song)
        try? context.save()
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

/// Färgfiltret: tryck på en eller flera färger. Låtar med någon av dem visas,
/// och de som har flest av färgerna hamnar först.
struct ColorFilterChips: View {
    @Binding var selected: Set<Int>
    let columns: [Int]
    @Environment(ColorCodes.self) private var codes

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(columns, id: \.self) { index in
                    let isOn = selected.contains(index)
                    Button {
                        if isOn { selected.remove(index) } else { selected.insert(index) }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(ColorCodes.colors[index]).frame(width: 10, height: 10)
                            Text(codes.names[index])
                                .font(.footnote.weight(isOn ? .semibold : .regular))
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(isOn ? ColorCodes.colors[index].opacity(0.25) : Color(.tertiarySystemFill), in: Capsule())
                        .overlay(Capsule().stroke(isOn ? ColorCodes.colors[index] : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }
}
