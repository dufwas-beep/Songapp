import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query private var songs: [Song]
    @Binding var selection: Song?

    @State private var query = ""
    @State private var showImporter = false
    @State private var importMessage: String?

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
                    description: Text("Tryck på + för att importera PDF:er och bilder från Filer.")
                )
            } else if visibleSongs.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Potpurri")
        .searchable(text: $query, placement: .sidebar, prompt: "Sök titel")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showImporter = true
                } label: {
                    Label("Importera", systemImage: "plus")
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: SongImporter.allowedTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importMessage = SongImporter.importFiles(urls, into: context).summary
            case .failure(let error):
                importMessage = "Importen misslyckades: \(error.localizedDescription)"
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
            Image(systemName: song.kind == .pdf ? "doc.text" : "photo")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(song.title)
                .lineLimit(1)
        }
    }
}
