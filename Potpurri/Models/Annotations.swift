import Foundation
import SwiftData

/// En gul lapp på en låt. Lappar som följer sidan har position och storlek i förhållande
/// till låtbladets bredd (så att de följer med när låten zoomas); lappar som sitter fast
/// på skärmen har position och storlek i punkter.
@Model
final class SongNote {
    var id: UUID = UUID()
    var songID: UUID = UUID()
    var text: String = ""
    var colorHex: String = NoteColors.yellow
    var x: Double = 0
    var y: Double = 0
    var width: Double = 0.3
    var height: Double = 0.12
    /// Fast på skärmen (ligger still när låten scrollar) i stället för att följa sidan.
    var pinned: Bool = false
    /// Låst textstorlek. Saknas den anpassas texten efter lappens storlek.
    /// För lappar som följer sidan i förhållande till bladets bredd, annars i punkter.
    var fixedFontSize: Double?
    var created: Date = Date()

    init(songID: UUID, text: String, x: Double, y: Double, width: Double, height: Double, pinned: Bool = false, colorHex: String = NoteColors.yellow) {
        self.id = UUID()
        self.songID = songID
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.pinned = pinned
        self.colorHex = colorHex
        self.created = Date()
    }
}

/// En rak markering med överstrykningspennan, i förhållande till låtbladets bredd.
@Model
final class Highlight {
    var id: UUID = UUID()
    var songID: UUID = UUID()
    var colorHex: String = NoteColors.yellow
    var x: Double = 0
    var y: Double = 0
    var width: Double = 0
    var height: Double = 0

    init(songID: UUID, colorHex: String, x: Double, y: Double, width: Double, height: Double) {
        self.id = UUID()
        self.songID = songID
        self.colorHex = colorHex
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Ett streck ritat med pennan. Punkterna (x, y, x, y …) och tjockleken i förhållande
/// till låtbladets bredd, så att strecket följer med när låten zoomas.
@Model
final class InkStroke {
    var id: UUID = UUID()
    var songID: UUID = UUID()
    var colorHex: String = NoteColors.inks[0]
    var lineWidth: Double = 0.0035
    var points: [Double] = []
    var created: Date = Date()

    init(songID: UUID, colorHex: String, lineWidth: Double, points: [Double]) {
        self.id = UUID()
        self.songID = songID
        self.colorHex = colorHex
        self.lineWidth = lineWidth
        self.points = points
        self.created = Date()
    }
}

enum NoteColors {
    static let yellow = "FFE873"
    /// Lapparnas färger: gul, rosa, grön, blå, orange, vit.
    static let notes = ["FFE873", "FFB3F9", "9BE7C4", "A8D8FF", "FFC68A", "FFFFFF"]
    /// Pennornas färger: gul, grön, rosa, blå, orange.
    static let pens = ["FFE45C", "6EE7A0", "FF8FE8", "7CC4FF", "FFB25C"]
    /// Ritpennans färger: svart, röd, blå, grön.
    static let inks = ["1C1C1E", "E5322D", "1F63D6", "2E9E4F"]
}

/// En hopplinje i en låt (högst 10). Ett tryck på skärmen, pedalen eller AirTurn
/// scrollar så att nästa linje (i nummerordning, 1, 2, 3 …) hamnar högst upp.
/// Numren bestämmer ordningen, så man kan hoppa tillbaka till t.ex. en refräng.
@Model
final class JumpMarker {
    var id: UUID = UUID()
    var songID: UUID = UUID()
    /// Position i bladet, i förhållande till bladets bredd.
    var y: Double = 0
    var number: Int = 1

    init(songID: UUID, y: Double, number: Int) {
        self.id = UUID()
        self.songID = songID
        self.y = y
        self.number = number
    }
}

/// En ackordstämpel på en låt. Grundton och bas sparas som tonhöjd (0 = C … 11 = B)
/// och stavas efter låtens tonart (F# i G-dur, Gb i Db-dur). Position i förhållande
/// till bladets bredd (vänsterkant och mitt på höjden).
@Model
final class ChordStamp {
    var id: UUID = UUID()
    var songID: UUID = UUID()
    var root: Int = 0
    var quality: String = ""
    var bass: Int?
    var x: Double = 0
    var y: Double = 0
    /// Ackord i samma grupp sitter ihop och flyttas tillsammans.
    var groupID: UUID?
    /// Stavning med b (Ab) i stället för # (G#). Bestäms av paletten när ackordet läggs ut,
    /// så att ackord i versen inte stavas om när man byter tonart för refrängen.
    var flats: Bool?

    init(songID: UUID, root: Int, quality: String, bass: Int? = nil, x: Double, y: Double, groupID: UUID? = nil) {
        self.id = UUID()
        self.songID = songID
        self.root = root
        self.quality = quality
        self.bass = bass
        self.x = x
        self.y = y
        self.groupID = groupID
    }
}

/// Ett ljudklipp i soundboarden. Originalfilen ändras aldrig – trim och volym sparas
/// som inställningar.
@Model
final class SoundClip {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "FB91FF"
    var fileName: String = ""
    var order: Int = 0
    /// Start och slut i sekunder (slut 0 = till slutet av filen).
    var trimStart: Double = 0
    var trimEnd: Double = 0
    /// Volym i dB, −12 … +6.
    var volumeDB: Double = 0

    init(name: String, fileName: String, order: Int, colorHex: String) {
        self.id = UUID()
        self.name = name
        self.fileName = fileName
        self.order = order
        self.colorHex = colorHex
    }

    var fileURL: URL {
        SongFileStore.url(for: fileName)
    }

    /// Fast palett för ljudknapparna.
    static let palette = ["FB91FF", "FF6B6B", "FFB25C", "FFE45C", "6EE7A0", "5CC8FF", "8B7CFF", "B0B0B8"]
}
