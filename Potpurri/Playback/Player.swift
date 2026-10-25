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
}
