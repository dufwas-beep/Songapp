import SwiftData
import SwiftUI
import UIKit

/// Dela låtar med någon annan som har Potpurri, t.ex. via AirDrop. Låtarna packas i en
/// .potpurri-fil med kategorier, notes, markeringar, hopplinjer och ackord. Den som tar
/// emot filen får låtarna tillagda i sitt bibliotek.
private struct ShareSongsModifier: ViewModifier {
    @Binding var songIDs: Set<UUID>?
    @Environment(\.modelContext) private var context
    @Environment(ColorCodes.self) private var codes
    @State private var fileURL: URL?
    @State private var progress = TaskProgress()

    func body(content: Content) -> some View {
        content
            .onChange(of: songIDs) { _, ids in
                guard let ids, !ids.isEmpty else { return }
                Task {
                    fileURL = try? await Backup.export(context: context, colorNames: codes.names, progress: progress, only: ids)
                    songIDs = nil
                }
            }
            .sheet(isPresented: Binding(get: { fileURL != nil }, set: { if !$0 { fileURL = nil } })) {
                if let fileURL {
                    ActivityView(items: [fileURL])
                }
            }
    }
}

extension View {
    /// Sätt `songIDs` för att dela de låtarna (delningsrutan öppnas när filen är klar).
    func shareSongs(_ songIDs: Binding<Set<UUID>?>) -> some View {
        modifier(ShareSongsModifier(songIDs: songIDs))
    }
}

/// iPadens delningsruta (AirDrop, Spara i Filer, Mail …).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Tar emot en .potpurri-fil (AirDrop, Filer, Mail): låtarna läggs till i biblioteket.
@MainActor
enum SharedSongsReceiver {
    static func receive(_ url: URL, context: ModelContext) async -> String {
        do {
            let (content, archive) = try Backup.read(url)
            let count = try await Backup.merge(content, archive: archive, context: context)
            if count == 0 {
                return content.songs.isEmpty ? "Filen innehöll inga låtar." : "Låtarna finns redan i biblioteket."
            }
            return count == 1 ? "1 låt lades till i biblioteket." : "\(count) låtar lades till i biblioteket."
        } catch {
            return "Filen kunde inte läsas: \(error.localizedDescription)"
        }
    }
}
