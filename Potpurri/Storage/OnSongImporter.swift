import Foundation
import SwiftData

/// Import från en OnSong-backup i två steg: först läses backupen in (så att man kan välja
/// låtar), sedan importeras de valda låtarna och låtlistorna. Statusfältet visar förloppet.
enum OnSongImporter {
    @MainActor
    static func read(_ url: URL, existingTitles: Set<String>, progress: TaskProgress) async throws -> OnSongBackup {
        progress.start("Läser OnSong-backup", total: 0)
        defer { progress.finish() }
        progress.currentName = "Hämtar backupfilen …"
        let local = try await Task.detached(priority: .userInitiated) {
            try OnSongBackup.copyToWorkDirectory(url)
        }.value
        progress.currentName = "Läser låtar och låtlistor …"
        do {
            return try await Task.detached(priority: .userInitiated) {
                try OnSongBackup.read(localBackup: local, existingTitles: existingTitles)
            }.value
        } catch {
            try? FileManager.default.removeItem(at: local.deletingLastPathComponent())
            throw error
        }
    }

    @MainActor
    static func importSongs(_ selectedIDs: Set<String>, from backup: OnSongBackup, existing: [Song], into context: ModelContext, progress: TaskProgress) async -> String {
        let selected = backup.candidates.filter { selectedIDs.contains($0.id) }
        progress.start("Importerar från OnSong", total: selected.count)
        defer {
            progress.finish()
            backup.cleanUp()
        }

        var songCount = 0
        var noteCount = 0
        var failed: [String] = []
        // OnSong-id → Potpurri-id, för att kunna bygga låtlistorna.
        var idMap: [String: UUID] = [:]
        var existingByTitle: [String: UUID] = [:]
        for song in existing {
            existingByTitle[song.title.lowercased()] = song.id
        }

        for candidate in selected {
            progress.currentName = candidate.title
            if let song = await makeSong(candidate, archive: backup.archive) {
                context.insert(song)
                idMap[candidate.id] = song.id
                if candidate.kind == .note { noteCount += 1 } else { songCount += 1 }
            } else {
                failed.append(candidate.title)
            }
            progress.done += 1
        }
        // Låtar som inte importerades för att de redan fanns får ändå sin plats i låtlistorna.
        for candidate in backup.candidates where idMap[candidate.id] == nil {
            if let id = existingByTitle[candidate.title.lowercased()] {
                idMap[candidate.id] = id
            }
        }

        let existingSetlists = (try? context.fetch(FetchDescriptor<Setlist>())) ?? []
        let existingNames = Set(existingSetlists.map { $0.name.lowercased() })
        var setlistCount = 0
        for list in backup.setlists where !existingNames.contains(list.name.lowercased()) {
            var ids: [UUID] = []
            var breaks: [Int] = []
            for (index, onSongID) in list.songIDs.enumerated() {
                if list.setBreaks.contains(index), !ids.isEmpty { breaks.append(ids.count) }
                if let id = idMap[onSongID] { ids.append(id) }
            }
            guard !ids.isEmpty else { continue }
            context.insert(Setlist(name: list.name, songIDs: ids, setBreaks: Array(Set(breaks)).sorted()))
            setlistCount += 1
        }
        try? context.save()

        var parts: [String] = []
        parts.append(songCount == 1 ? "1 låt" : "\(songCount) låtar")
        if noteCount > 0 { parts.append(noteCount == 1 ? "1 anteckning" : "\(noteCount) anteckningar") }
        if setlistCount > 0 { parts.append(setlistCount == 1 ? "1 låtlista" : "\(setlistCount) låtlistor") }
        var summary = Self.join(parts) + " importerades."
        if !failed.isEmpty {
            summary += "\nKunde inte importera: " + failed.prefix(10).joined(separator: ", ") + (failed.count > 10 ? " m.fl." : "")
        }
        return summary
    }

    /// Packar upp låtens fil i bakgrunden och skapar låten.
    @MainActor
    private static func makeSong(_ candidate: OnSongCandidate, archive: ZipArchive) async -> Song? {
        switch candidate.content {
        case .text(let text):
            return Song(title: candidate.title, kind: .text, text: text, key: candidate.key, importedNote: candidate.note)
        case .file(let entryName):
            let kind = candidate.kind
            let stored: (fileName: String, text: String?)? = await Task.detached(priority: .userInitiated) { () -> (fileName: String, text: String?)? in
                guard let entry = archive.entry(named: entryName), let data = try? archive.data(for: entry) else { return nil }
                if kind == .note {
                    return ("", OnSongBackup.decodeText(data))
                }
                guard let fileName = try? SongFileStore.store(data, pathExtension: (entryName as NSString).pathExtension) else { return nil }
                return (fileName, nil)
            }.value
            guard let stored else { return nil }
            return Song(title: candidate.title, kind: kind, fileName: stored.fileName, text: stored.text, key: candidate.key, importedNote: candidate.note)
        }
    }

    /// "3 låtar, 2 anteckningar och 1 låtlista"
    private static func join(_ parts: [String]) -> String {
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " och " + parts.last!
    }
}
