import Foundation
import SwiftData

/// En kvällslogg: vilka låtar som spelades under en spelning, i ordning. "Ny spelning"
/// startar en ny logg som heter datum och tid (t.ex. "Lör 24 okt 21:15").
@Model
final class GigLog {
    var id: UUID = UUID()
    var name: String = ""
    var started: Date = Date()
    var entries: [Entry] = []

    struct Entry: Codable, Hashable {
        var songID: UUID
        var title: String
        var time: Date
    }

    init(started: Date = Date()) {
        self.id = UUID()
        self.started = started
        self.name = Self.defaultName(for: started)
    }

    static func defaultName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "EEE d MMM HH:mm"
        let text = formatter.string(from: date).replacingOccurrences(of: ".", with: "")
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// Skriver till kvällsloggen.
@MainActor
enum GigLogger {
    /// Den pågående loggen (den senast startade), skapas om ingen finns.
    static func current(in context: ModelContext, since gigStart: Date) -> GigLog {
        var descriptor = FetchDescriptor<GigLog>(sortBy: [SortDescriptor(\.started, order: .reverse)])
        descriptor.fetchLimit = 1
        if let latest = try? context.fetch(descriptor).first, latest.started >= gigStart.addingTimeInterval(-1) {
            return latest
        }
        let log = GigLog(started: max(gigStart, Date().addingTimeInterval(-12 * 3600)))
        context.insert(log)
        return log
    }

    /// En låt har spelats (varit huvudlåt i 30 sekunder).
    static func played(_ song: Song, in context: ModelContext, since gigStart: Date) {
        let log = current(in: context, since: gigStart)
        // Hela listan sätts om – en ändring inne i listan märks annars inte och sparas inte.
        var entries = log.entries
        entries.append(.init(songID: song.id, title: song.title, time: Date()))
        log.entries = entries
        try? context.save()
    }
}
