import Foundation
import Observation

/// Det som gäller medan man spelar: kön för nästa/förra låt, scenlåset, kvällens
/// spelade låtar, valda förslagsfärger, fästa förslag och förhandsrutan.
@MainActor
@Observable
final class Player {
    /// Låtarna i den lista man senast valde en låt ur, i ordning.
    var queue: [UUID] = []
    /// Scenlås: bara scrolla, byta låt och autoscroll – inget kan ändras av misstag.
    var isLocked = false
    /// Färgerna som styr förslagen. Följer med till nästa låt.
    var activeColors: Set<Int> = []
    /// Låtar som fästs överst bland förslagen för kvällen.
    var pinned: [UUID] = []
    /// Låten i förhandsrutan under huvudlåten.
    var previewID: UUID?
    /// Förslaget som spelas just nu (valt i förhandsrutan). Då bläddrar pedalen bara
    /// inom låten och listornas kö ändras inte.
    var playingSuggestionID: UUID?
    /// När kvällen började ("Ny spelning"). Låtar spelade sedan dess är gråa.
    private(set) var gigStart: Date {
        didSet { UserDefaults.standard.set(gigStart, forKey: "gigStart") }
    }

    init() {
        gigStart = UserDefaults.standard.object(forKey: "gigStart") as? Date ?? .distantPast
    }

    func isPlayedTonight(_ song: Song) -> Bool {
        guard let played = song.lastPlayed else { return false }
        return played >= gigStart
    }

    /// Ny spelning: nollställer gråmarkeringarna och de fästa förslagen.
    func newGig() {
        gigStart = Date()
        pinned = []
        previewID = nil
    }

    /// Valda färger följer med: nästa låt behåller de valda färger den har, annars alla sina.
    func updateColors(for song: Song?) {
        guard let song else { return }
        let kept = activeColors.intersection(song.colorTags)
        activeColors = kept.isEmpty ? Set(song.colorTags) : kept
    }

    func togglePin(_ id: UUID) {
        if pinned.contains(id) {
            pinned.removeAll { $0 == id }
        } else {
            pinned.insert(id, at: 0)
        }
    }
}
