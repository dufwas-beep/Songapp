import Foundation
import SwiftData

/// Vilken sorts låtblad en låt består av.
enum SongKind: String, Codable {
    case pdf
    case image
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

    init(title: String, kind: SongKind, fileName: String) {
        self.id = UUID()
        self.title = title
        self.kindRaw = kind.rawValue
        self.fileName = fileName
        self.dateAdded = Date()
    }

    var kind: SongKind {
        SongKind(rawValue: kindRaw) ?? .pdf
    }

    var fileURL: URL {
        SongFileStore.url(for: fileName)
    }
}
