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

    /// Sökning på titel och vald sortering.
    private var visibleSongs: [Song] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let filtered = q.isEmpty ? songs : songs.filter { $0.title.localizedCaseInsensitiveContains(q) }
        switch sort {
        case .name:
            return filtered.sorted(by: Song.swedishOrder)
        case .added:
            return filtered.sorted { $0.dateAdded > $1.dateAdded }
        case .lastPlayed:
            return filtered.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        case .mostPlayed:
            return filtered.sorted { $0.playCount != $1.playCount ? $0.playCount > $1.playCount : Song.swedishOrder($0, $1) }
        }
    }

    private var showsAlphabet: Bool {
        sort == .name && query.isEmpty && songs.count > 20
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SearchField(text: $query, prompt: "Sök titel")
                sortMenu
                importMenu
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            let list = visibleSongs
            ScrollViewReader { proxy in
                List(selection: $selection) {
                    ForEach(list) { song in
                        SongRow(song: song)
                            .tag(song)
                            .id(song.id)
                            .padding(.trailing, showsAlphabet ? 18 : 0)
                            .contextMenu {
                                if !player.isLocked { rowMenu(for: song) }
                            }
                    }
                    .onDelete(perform: deleteAction(in: list))
                }
                .listStyle(.plain)
                // Nästa/förra låt följer biblioteket när man valt en låt här.
                .onChange(of: selection) { _, song in
                    if let song, list.contains(song) {
                        player.queue = list.map(\.id)
                    }
                }
                .overlay(alignment: .trailing) {
                    if showsAlphabet {
                        AlphabetScrubber(available: Set(songs.map(\.indexLetter))) { letter in
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
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if progress.isRunning {
                ProgressBanner(progress: progress)
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

    var body: some View {
        HStack(spacing: 10) {
            Text(song.title)
                .lineLimit(1)
            // Bara anteckningar (t.ex. quizmanus) märks – om en låt är PDF eller bild spelar ingen roll.
            if song.kind == .note {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Anteckning")
            }
            Spacer(minLength: 0)
            if let key = song.key {
                Text(key)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
