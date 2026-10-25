import Foundation
import Observation

/// Det som gäller medan man spelar: vilken lista låtarna kommer ifrån (för nästa/förra låt)
/// och om scenlåset är på.
@MainActor
@Observable
final class Player {
    /// Låtarna i den lista man senast valde en låt ur, i ordning.
    var queue: [UUID] = []
    /// Scenlås: bara scrolla, byta låt och autoscroll – inget kan ändras av misstag.
    var isLocked = false

    func next(after id: UUID?) -> UUID? {
        guard let id, let index = queue.firstIndex(of: id), index + 1 < queue.count else { return nil }
        return queue[index + 1]
    }

    func previous(before id: UUID?) -> UUID? {
        guard let id, let index = queue.firstIndex(of: id), index > 0 else { return nil }
        return queue[index - 1]
    }
}
