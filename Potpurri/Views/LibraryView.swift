import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query private var songs: [Song]
    @Binding var selection: Song?

    @State private var query = ""
    @State private var showImporter = false
    @State private var importsOnSong = false
    @State private var onSongBackup: OnSongBackup?
    @State private var importMessage: String?
    @State private var progress = TaskProgress()

    private static let swedish = Locale(identifier: "sv_SE")

    /// Sökning på titel och svensk sortering (Å, Ä, Ö sist).
    private var visibleSongs: [Song] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let filtered = q.isEmpty ? songs : songs.filter { $0.title.localizedCaseInsensitiveContains(q) }
        return filtered.sorted {
            $0.title.compare($1.title, options: [.caseInsensitive, .numeric], range: nil, locale: Self.swedish) == .orderedAscending
        }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(visibleSongs) { song in
                SongRow(song: song)
                    .tag(song)
            }
            .onDelete(perform: delete)
        }
        .overlay {
            if songs.isEmpty {
                ContentUnavailableView(
                    "Inga låtar ännu",
                    systemImage: "music.note.list",
                    description: Text("Tryck på + för att importera PDF:er och bilder från Filer, eller en OnSong-backup.")
                )
            } else if visibleSongs.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if progress.isRunning {
                ProgressBanner(progress: progress)
            }
        }
        .navigationTitle("Potpurri")
        .searchable(text: $query, placement: .sidebar, prompt: "Sök titel")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
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
                    Label("Importera", systemImage: "plus")
                }
                .disabled(progress.isRunning)
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

    private func delete(at offsets: IndexSet) {
        let list = visibleSongs
        for index in offsets {
            let song = list[index]
            if selection == song { selection = nil }
            SongFileStore.delete(song.fileName)
            context.delete(song)
        }
        try? context.save()
    }
}

private struct SongRow: View {
    let song: Song

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: song.kind.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(song.title)
                .lineLimit(1)
        }
    }
}
