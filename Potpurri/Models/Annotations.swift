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

enum NoteColors {
    static let yellow = "FFE873"
    /// Lapparnas färger: gul, rosa, grön, blå, orange, vit.
    static let notes = ["FFE873", "FFB3F9", "9BE7C4", "A8D8FF", "FFC68A", "FFFFFF"]
    /// Pennornas färger: gul, grön, rosa, blå, orange.
    static let pens = ["FFE45C", "6EE7A0", "FF8FE8", "7CC4FF", "FFB25C"]
}
