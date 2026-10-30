import Foundation
import SwiftData

/// Vilken sorts låtblad en låt består av.
enum SongKind: String, Codable {
    case pdf
    case image
    /// Text med ackord (t.ex. skriven i OnSong) – visas med ackorden ovanför texten.
    case text
    /// Anteckning, t.ex. ett quizmanus – vanlig text utan ackord.
    case note
}

/// En låt i biblioteket. Själva filen ligger i `SongFileStore`; här sparas bara
/// uppgifter om den. Alla fält har standardvärden så att iCloud-synk (CloudKit)
/// kan slås på senare utan att modellen behöver göras om.
@Model
final class Song {
    var id: UUID = UUID()
    var title: String = ""
    var kindRaw: String = SongKind.pdf.rawValue
    /// Filnamnet i appens egen låtmapp – originalfilen ändras aldrig.
    var fileName: String = ""
    var dateAdded: Date = Date()
    var lastPlayed: Date?
    var playCount: Int = 0
    /// Texten för textlåtar och anteckningar (de har ingen fil).
    var text: String?
    /// Låtens tonart, t.ex. "G" eller "Am".
    var key: String?
    /// Anteckning som följde med från OnSong. Blir en gul lapp när lapparna finns.
    var importedNote: String?
    /// Låtens längd för autoscroll, i sekunder (0:30–10:00). Saknas den används 3:00.
    var autoscrollSeconds: Int?
    /// Låtens zoom (nyp) i förhållande till "hela bredden" (1 = anpassad efter bredden).
    /// Gäller PDF:er, bilder och textlåtar.
    var pdfZoom: Double?
    /// "Mina anteckningar" – det gula fältet ovanför låten i Lådan.
    var drawerNote: String?
    /// Låttexten för sökning: utläst ur PDF:en eller textigenkänd ur bilden.
    /// nil = inte indexerad än.
    var searchText: String?
    /// Tonarten låten börjar i (från första ackordet på låten). Visas i listorna.
    var startKey: String?
    /// Ackordstämplarnas storlek i förhållande till bladets bredd (nil = standard).
    var chordSize: Double?
    /// Låtens färgkoder (0–4, se `ColorCodes`).
    var colorTags: [Int] = []
    /// Var man senast hade flyttat låtbladet (i förhållande till bladets bredd), så att
    /// en inzoomad låt öppnas där man hade den.
    var scrollX: Double?
    var scrollY: Double?
    /// Quiz (t.ex. "HLS 45"): låtarna som ska vara med i quizet, i ordning.
    var quizSongIDs: [UUID] = []

    init(title: String, kind: SongKind, fileName: String = "", text: String? = nil, key: String? = nil, importedNote: String? = nil) {
        self.id = UUID()
        self.title = title
        self.kindRaw = kind.rawValue
        self.fileName = fileName
        self.dateAdded = Date()
        self.text = text
        self.key = key
        self.importedNote = importedNote
    }

    var kind: SongKind {
        SongKind(rawValue: kindRaw) ?? .pdf
    }

    /// Tonarten som visas i listorna: den låten börjar i, annars den sparade tonarten.
    var displayKey: String? {
        startKey ?? key
    }

    func toggleColor(_ index: Int) {
        if colorTags.contains(index) {
            colorTags.removeAll { $0 == index }
        } else {
            colorTags = (colorTags + [index]).sorted()
        }
    }

    /// Textlåt som gjorts redigerbar från en PDF – kan återställas till PDF:en.
    var canRestorePDF: Bool {
        kind == .text && hasFile && (fileName as NSString).pathExtension.lowercased() == "pdf"
    }

    /// Matchar sökningen titeln eller låttexten?
    /// Sökningen jämförs mot förenklad text (små bokstäver, utan accenter) som sparas
    /// i minnet – att jämföra med accentlös sökning i hela låttexten varje gång var segt.
    func matches(_ query: String) -> Bool {
        if title.localizedCaseInsensitiveContains(query) { return true }
        let raw = (kind == .text || kind == .note) ? (self.text ?? "") : (searchText ?? "")
        guard !raw.isEmpty else { return false }
        return SearchCache.shared.folded(raw, for: id).contains(SearchCache.fold(query))
    }

    /// Har låten en egen fil (PDF eller bild)?
    var hasFile: Bool {
        !fileName.isEmpty
    }

    var fileURL: URL {
        SongFileStore.url(for: fileName)
    }
}

extension Song {
    private static let swedish = Locale(identifier: "sv_SE")

    /// Svensk bokstavsordning (Å, Ä, Ö sist) och siffror i nummerordning.
    static func swedishOrder(_ a: Song, _ b: Song) -> Bool {
        TitleOrder.shared.rank(of: a.title) < TitleOrder.shared.rank(of: b.title)
    }

    static func compareTitles(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .numeric], range: nil, locale: swedish) == .orderedAscending
    }

    /// Bokstaven låten sorteras under i alfabetet vid sidan av biblioteket.
    var indexLetter: String { Self.indexLetter(of: title) }

    /// Bokstaven i alfabetet vid sidan av listan (även för låtlistornas namn).
    static func indexLetter(of title: String) -> String {
        guard let first = title.trimmingCharacters(in: .whitespaces).first else { return "#" }
        let upper = String(first).uppercased()
        if ["Å", "Ä", "Ö"].contains(upper) { return upper }
        // É, Ü och liknande hamnar under sin grundbokstav.
        let plain = upper.folding(options: .diacriticInsensitive, locale: swedish)
        if plain.count == 1, let letter = plain.first, letter >= "A", letter <= "Z" {
            return plain
        }
        return "#"
    }
}

/// Kom ihåg varje titels plats i bokstavsordningen. Svensk jämförelse är långsam, och
/// listorna sorteras om varje gång man byter låt – nu jämförs bara heltal.
private final class TitleOrder: @unchecked Sendable {
    static let shared = TitleOrder()
    private let lock = NSLock()
    private var sorted: [String] = []
    private var ranks: [String: Int] = [:]

    func rank(of title: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        if let rank = ranks[title] { return rank }
        // Ny titel: sätt in den på rätt plats och numrera om.
        var low = 0, high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if Song.compareTitles(sorted[mid], title) { low = mid + 1 } else { high = mid }
        }
        sorted.insert(title, at: low)
        ranks.removeAll(keepingCapacity: true)
        for (index, known) in sorted.enumerated() { ranks[known] = index }
        return low
    }
}

/// Låttexterna i förenklad form för sökningen, en per låt. Görs om bara när texten ändras.
final class SearchCache: @unchecked Sendable {
    static let shared = SearchCache()
    private let lock = NSLock()
    private var texts: [UUID: (length: Int, text: String)] = [:]

    func folded(_ raw: String, for id: UUID) -> String {
        let length = raw.utf16.count
        lock.lock()
        defer { lock.unlock() }
        if let hit = texts[id], hit.length == length { return hit.text }
        let text = Self.fold(raw)
        texts[id] = (length, text)
        return text
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
