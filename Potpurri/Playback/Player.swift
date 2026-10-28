import Foundation
import QuartzCore
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
    /// Markeringspennan: av, en färg eller sudd.
    var pen: AnnotationOverlay.Pen = .off
    /// Visa/dölj alla lappar.
    var notesHidden = false
    /// När nedräkningstimern (vid klockan) når noll, t.ex. slutet av ett set.
    var timerEnd: Date?
    /// Redigera hopplinjer (lägg till, flytta, numrera).
    var editingMarkers = false
    /// Visa hopplinjerna även när man inte redigerar dem.
    var showsMarkers = true
    /// Ackordpaletten är öppen (då kan ackorden flyttas och ändras).
    var chordsOn = false
    /// "Välj ackord": tryck på ackord för att markera dem.
    var choosingChords = false
    var selectedChords: Set<UUID> = []
    /// Kopierad ackordsekvens (ackord med avstånd till det första) som väntar på att
    /// klistras in med ett tryck på låten.
    var chordClipboard: [CopiedChord] = []
    var pastingChords = false

    struct CopiedChord {
        let root: Int
        let quality: String
        let bass: Int?
        let flats: Bool
        let dx: Double
        let dy: Double
    }

    /// Låten som byter namn / vars text redigeras just nu.
    var renamingSongID: UUID?
    var editingTextSongID: UUID?
    /// Indexering av låttext (för sökning) i bakgrunden.
    let indexing = TaskProgress()
    /// Lådan: vad som ligger i den (en låt eller anteckning) och om den är utdragen.
    var drawerSongID: UUID?
    var drawerOpen = false
    /// Soundboardens kolumn längs högerkanten.
    var soundboardOpen = false
    /// Autoscroll är igång (LP:n snurrar sakta).
    var isAutoscrolling = false
    /// Ökar för varje tryck på LP:n – förslagsrutan kör då lyckohjulet.
    var lotteryRuns = 0
    /// Låten som lyckohjulets markering står på just nu.
    var lotteryHighlight: UUID?
    /// Ökar vid dubbeltryck på LP:n – duvan flyger.
    var doveFlights = 0
    /// Skärmsläckaren (pausen) visas.
    var screensaverOn = false
    /// Snabb snurr på LP:n (t.ex. vid "Ny spelning").
    var spinBurst = 0
    /// Noten som redigeras just nu.
    var editingNoteID: UUID?
    /// Låtar som ska tas bort (t.ex. testlåtarna). ContentView släpper dem först ur vyerna.
    var songsToDelete: Set<UUID> = []
    /// Den låt som visas (speglas från ContentView). Biblioteket läser den bara i raderna,
    /// så att inte hela biblioteket ritas om vid varje låtbyte.
    var selectedSongID: UUID?
    /// Biblioteket ber ContentView att visa en låt.
    var requestedSongID: UUID?
    /// Låtarna i den låtlista man senast valde en låt ur (nil = biblioteket).
    /// Next kan visa bara dem.
    var setlistSongIDs: [UUID]?
    /// Tidtagaren: när låtbytet började och hur lång tid det senaste tog.
    @ObservationIgnored var switchStartedAt: CFTimeInterval?
    @ObservationIgnored private var switchSelectedAt: CFTimeInterval?
    @ObservationIgnored private var switchViewAt: CFTimeInterval?
    var lastSwitchReport: String?

    func startSwitchTimer() {
        switchStartedAt = CACurrentMediaTime()
        switchSelectedAt = nil
        switchViewAt = nil
    }

    /// Steg 1: låten är vald. Steg 2: låtvyn har byggts.
    func markSwitchSelected() {
        if switchStartedAt != nil, switchSelectedAt == nil { switchSelectedAt = CACurrentMediaTime() }
    }

    func markSwitchViewBuilt() {
        if switchStartedAt != nil, switchViewAt == nil { switchViewAt = CACurrentMediaTime() }
    }

    /// Steg 3: låten syns (första sidan är på plats). Mäts efter nästa ritning.
    func finishSwitchTimer(kind: String) {
        guard let start = switchStartedAt else { return }
        let selected = switchSelectedAt ?? start
        let view = switchViewAt ?? selected
        switchStartedAt = nil
        DispatchQueue.main.async {
            let end = CACurrentMediaTime()
            let ms = { (seconds: CFTimeInterval) in Int(seconds * 1000) }
            self.lastSwitchReport = "Låtbyte \(ms(end - start)) ms · vald \(ms(selected - start)) · vy \(ms(view - selected)) · sida \(ms(end - view)) · \(kind)"
        }
    }
    /// När kvällen började ("Ny spelning"). Låtar spelade sedan dess är gråa.
    /// Nästa dag (efter kl. 06) börjar automatiskt en ny spelning.
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

    /// En ny dag (efter kl. 06) börjar automatiskt en ny spelning. Spelar man efter
    /// midnatt räknas det fortfarande som samma kväll.
    func startNewGigIfStale() {
        let now = Date()
        let calendar = Calendar.current
        var dayStart = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: now) ?? now
        if dayStart > now { dayStart = calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart }
        if gigStart < dayStart { newGig() }
    }

    /// Ny spelning: nollställer gråmarkeringarna och de fästa förslagen.
    func newGig() {
        spinBurst += 1
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
