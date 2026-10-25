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

    /// Symbol i listorna.
    var symbolName: String {
        switch self {
        case .pdf: return "doc.text"
        case .image: return "photo"
        case .text: return "music.note"
        case .note: return "note.text"
        }
    }
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
