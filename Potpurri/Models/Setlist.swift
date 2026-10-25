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

/// En rad i en låtlista: en låt eller en setgräns.
enum SetlistItem: Hashable {
    case song(UUID)
    case setBreak
}

extension Setlist {
    /// Låtar och setgränser i ordning – så som listan visas och dras om.
    var items: [SetlistItem] {
        get {
            var result: [SetlistItem] = []
            for index in 0...songIDs.count {
                let breaksHere = setBreaks.filter { $0 == index }.count
                result.append(contentsOf: Array(repeating: SetlistItem.setBreak, count: breaksHere))
                if index < songIDs.count {
                    result.append(.song(songIDs[index]))
                }
            }
            return result
        }
        set {
            var ids: [UUID] = []
            var breaks: [Int] = []
            for item in newValue {
                switch item {
                case .song(let id): ids.append(id)
                case .setBreak: breaks.append(ids.count)
                }
            }
            songIDs = ids
            setBreaks = breaks
        }
    }

    /// Tar bort en låt överallt i listan (t.ex. när låten tas bort ur biblioteket).
    func removeSong(_ id: UUID) {
        items = items.filter { $0 != .song(id) }
    }
}
