import Foundation
import Observation

/// Hur långt ett längre jobb (import, senare även indexering) har kommit,
/// så att man ser att appen arbetar och ungefär hur länge det är kvar.
@MainActor
@Observable
final class TaskProgress {
    private(set) var title = ""
    private(set) var total = 0
    var done = 0
    var currentName = ""
    private(set) var isRunning = false
    private var startDate = Date()

    func start(_ title: String, total: Int) {
        self.title = title
        self.total = total
        done = 0
        currentName = ""
        startDate = Date()
        isRunning = true
    }

    func finish() {
        isRunning = false
    }

    var fraction: Double {
        total == 0 ? 0 : Double(done) / Double(total)
    }

    /// Ungefärlig tid kvar, räknad på hur lång tid de hittills klara filerna tagit.
    func remainingText(at now: Date) -> String {
        guard done > 0 else { return "Beräknar tid kvar …" }
        let elapsed = now.timeIntervalSince(startDate)
        let left = max(0, elapsed / Double(done) * Double(total - done))
        if left < 5 { return "Strax klart" }
        if left < 60 { return "Ca \(Int(left.rounded())) s kvar" }
        return "Ca \(Int((left / 60).rounded(.up))) min kvar"
    }
}
