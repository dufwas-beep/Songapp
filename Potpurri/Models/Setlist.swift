import Foundation
import SwiftData

/// En låtlista, t.ex. en kvälls spelning. Låtarna lagras som id:n i ordning
/// och setgränserna som de platser i listan där ett nytt set börjar.
@Model
final class Setlist {
    var id: UUID = UUID()
    var name: String = ""
    var created: Date = Date()
    var songIDs: [UUID] = []
    /// Index i `songIDs` där ett nytt set börjar.
    var setBreaks: [Int] = []

    init(name: String, songIDs: [UUID] = [], setBreaks: [Int] = []) {
        self.id = UUID()
        self.name = name
        self.created = Date()
        self.songIDs = songIDs
        self.setBreaks = setBreaks
    }
}
