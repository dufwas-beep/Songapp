import SwiftUI

struct SongDetailView: View {
    let song: Song?

    var body: some View {
        if let song {
            Group {
                if !FileManager.default.fileExists(atPath: song.fileURL.path) {
                    ContentUnavailableView(
                        "Filen saknas",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Låtens fil hittades inte. Importera den igen.")
                    )
                } else {
                    switch song.kind {
                    case .pdf:
                        PDFKitView(url: song.fileURL)
                    case .image:
                        ImageSongView(url: song.fileURL)
                    }
                }
            }
            .id(song.id)
            .navigationTitle(song.title)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView(
                "Välj en låt",
                systemImage: "music.note",
                description: Text("Välj en låt i listan till vänster.")
            )
        }
    }
}
