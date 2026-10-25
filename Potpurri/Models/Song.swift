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
        a.title.compare(b.title, options: [.caseInsensitive, .numeric], range: nil, locale: swedish) == .orderedAscending
    }

    /// Bokstaven låten sorteras under i alfabetet vid sidan av biblioteket.
    var indexLetter: String {
        guard let first = title.trimmingCharacters(in: .whitespaces).first else { return "#" }
        let upper = String(first).uppercased()
        if ["Å", "Ä", "Ö"].contains(upper) { return upper }
        // É, Ü och liknande hamnar under sin grundbokstav.
        let plain = upper.folding(options: .diacriticInsensitive, locale: Self.swedish)
        if plain.count == 1, let letter = plain.first, letter >= "A", letter <= "Z" {
            return plain
        }
        return "#"
    }
}
