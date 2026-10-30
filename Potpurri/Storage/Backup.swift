import Foundation
import SwiftData

/// Säkerhetskopia av hela biblioteket – låtar, listor, notes, markeringar, hopplinjer,
/// ackord, ljud, kvällsloggar och inställningar – som en fil (.potpurri) i Filer. Kan läsas
/// in igen, t.ex. på en ny iPad. Filen är ett zip-arkiv med `backup.json` och alla filer.
enum Backup {
    struct Content: Codable {
        var version = 1
        var created = Date()
        var colorNames: [String] = []
        var songs: [SongData] = []
        var setlists: [SetlistData] = []
        var notes: [NoteData] = []
        var highlights: [HighlightData] = []
        /// Pennans streck (finns inte i äldre kopior).
        var strokes: [StrokeData]? = nil
        var markers: [MarkerData] = []
        var chords: [ChordData] = []
        var sounds: [SoundData] = []
        var logs: [LogData] = []
    }

    struct SongData: Codable {
        var id: UUID, title: String, kindRaw: String, fileName: String, dateAdded: Date
        var lastPlayed: Date?, playCount: Int, text: String?, key: String?, importedNote: String?
        var autoscrollSeconds: Int?, colorTags: [Int], pdfZoom: Double?, chordSize: Double?
        var startKey: String?, searchText: String?, drawerNote: String?
        var quizSongIDs: [UUID]?
    }

    struct SetlistData: Codable { var id: UUID, name: String, created: Date, songIDs: [UUID], setBreaks: [Int] }
    struct NoteData: Codable { var id: UUID, songID: UUID, text: String, colorHex: String, x: Double, y: Double, width: Double, height: Double, pinned: Bool, fixedFontSize: Double?, created: Date }
    struct HighlightData: Codable { var id: UUID, songID: UUID, colorHex: String, x: Double, y: Double, width: Double, height: Double }
    struct StrokeData: Codable { var id: UUID, songID: UUID, colorHex: String, lineWidth: Double, points: [Double], created: Date }
    struct MarkerData: Codable { var id: UUID, songID: UUID, y: Double, number: Int }
    struct ChordData: Codable { var id: UUID, songID: UUID, root: Int, quality: String, bass: Int?, x: Double, y: Double, groupID: UUID?, flats: Bool? }
    struct SoundData: Codable { var id: UUID, name: String, colorHex: String, fileName: String, order: Int, trimStart: Double, trimEnd: Double, volumeDB: Double }
    struct LogData: Codable { var id: UUID, name: String, started: Date, entries: [GigLog.Entry] }

    // MARK: Spara

    /// Samlar allt och skriver arkivet till en tillfällig fil, som sedan sparas i Filer.
    /// `only`: bara de här låtarna (med sina notes, markeringar, hopplinjer och ackord) –
    /// för att dela låtar med någon annan, t.ex. via AirDrop.
    @MainActor
    static func export(context: ModelContext, colorNames: [String], progress: TaskProgress, only: Set<UUID>? = nil) async throws -> URL {
        var songs = try context.fetch(FetchDescriptor<Song>())
        var sounds = try context.fetch(FetchDescriptor<SoundClip>())
        if let only {
            songs = songs.filter { only.contains($0.id) }
            sounds = []
        }
        let belongs = { (songID: UUID) in only?.contains(songID) ?? true }
        var content = Content(colorNames: colorNames)
        content.songs = songs.map {
            SongData(id: $0.id, title: $0.title, kindRaw: $0.kindRaw, fileName: $0.fileName, dateAdded: $0.dateAdded,
                     lastPlayed: $0.lastPlayed, playCount: $0.playCount, text: $0.text, key: $0.key, importedNote: $0.importedNote,
                     autoscrollSeconds: $0.autoscrollSeconds, colorTags: $0.colorTags, pdfZoom: $0.pdfZoom, chordSize: $0.chordSize,
                     startKey: $0.startKey, searchText: $0.searchText, drawerNote: $0.drawerNote,
                     quizSongIDs: $0.quizSongIDs.isEmpty ? nil : $0.quizSongIDs)
        }
        if only == nil { content.setlists = try context.fetch(FetchDescriptor<Setlist>()).map { SetlistData(id: $0.id, name: $0.name, created: $0.created, songIDs: $0.songIDs, setBreaks: $0.setBreaks) } }
        content.notes = try context.fetch(FetchDescriptor<SongNote>()).filter { belongs($0.songID) }.map { NoteData(id: $0.id, songID: $0.songID, text: $0.text, colorHex: $0.colorHex, x: $0.x, y: $0.y, width: $0.width, height: $0.height, pinned: $0.pinned, fixedFontSize: $0.fixedFontSize, created: $0.created) }
        content.highlights = try context.fetch(FetchDescriptor<Highlight>()).filter { belongs($0.songID) }.map { HighlightData(id: $0.id, songID: $0.songID, colorHex: $0.colorHex, x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        content.strokes = try context.fetch(FetchDescriptor<InkStroke>()).filter { belongs($0.songID) }.map { StrokeData(id: $0.id, songID: $0.songID, colorHex: $0.colorHex, lineWidth: $0.lineWidth, points: $0.points, created: $0.created) }
        content.markers = try context.fetch(FetchDescriptor<JumpMarker>()).filter { belongs($0.songID) }.map { MarkerData(id: $0.id, songID: $0.songID, y: $0.y, number: $0.number) }
        content.chords = try context.fetch(FetchDescriptor<ChordStamp>()).filter { belongs($0.songID) }.map { ChordData(id: $0.id, songID: $0.songID, root: $0.root, quality: $0.quality, bass: $0.bass, x: $0.x, y: $0.y, groupID: $0.groupID, flats: $0.flats) }
        content.sounds = sounds.map { SoundData(id: $0.id, name: $0.name, colorHex: $0.colorHex, fileName: $0.fileName, order: $0.order, trimStart: $0.trimStart, trimEnd: $0.trimEnd, volumeDB: $0.volumeDB) }
        if only == nil { content.logs = try context.fetch(FetchDescriptor<GigLog>()).map { LogData(id: $0.id, name: $0.name, started: $0.started, entries: $0.entries) } }

        let files = Set(songs.map(\.fileName) + sounds.map(\.fileName)).filter { !$0.isEmpty }.sorted()
        let json = try JSONEncoder().encode(content)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        var name = "Potpurri \(formatter.string(from: Date()))"
        if only != nil {
            // Delade låtar heter som låten (eller "3 låtar från Potpurri").
            name = songs.count == 1 ? songs[0].title.replacingOccurrences(of: "/", with: "-") : "\(songs.count) låtar från Potpurri"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".potpurri")
        try? FileManager.default.removeItem(at: url)

        progress.start(only == nil ? "Sparar säkerhetskopia" : "Förbereder delning", total: files.count)
        defer { progress.finish() }
        let writer = try ZipWriter(url: url)
        try writer.add(name: "backup.json", data: json)
        for name in files {
            progress.currentName = name
            let fileURL = SongFileStore.url(for: name)
            if let data = await Task.detached(priority: .userInitiated, operation: { try? Data(contentsOf: fileURL) }).value {
                try writer.add(name: "files/" + name, data: data)
            }
            progress.done += 1
        }
        try writer.finish()
        return url
    }

    // MARK: Läsa in

    /// Läser säkerhetskopian (innehållet visas innan något ersätts).
    static func read(_ url: URL) throws -> (content: Content, archive: ZipArchive) {
        let local = try OnSongBackup.copyToWorkDirectory(url)
        let archive = try ZipArchive(url: local)
        guard let entry = archive.entry(named: "backup.json") else { throw ZipError.notAZip }
        let content = try JSONDecoder().decode(Content.self, from: archive.data(for: entry))
        return (content, archive)
    }

    /// Lägger till låtarna i filen (t.ex. delade via AirDrop) utan att ta bort något.
    /// Låtar som redan finns (samma låt, t.ex. delad två gånger) hoppas över.
    /// Svarar med hur många låtar som lades till.
    @MainActor
    static func merge(_ content: Content, archive: ZipArchive, context: ModelContext) async throws -> Int {
        let existing = Set(try context.fetch(FetchDescriptor<Song>()).map(\.id))
        let added = content.songs.filter { !existing.contains($0.id) }
        let addedIDs = Set(added.map(\.id))
        for item in added where !item.fileName.isEmpty {
            let target = SongFileStore.url(for: item.fileName)
            guard !FileManager.default.fileExists(atPath: target.path) else { continue }
            let name = item.fileName
            _ = await Task.detached(priority: .userInitiated) { () -> Bool in
                guard let entry = archive.entry(named: "files/" + name), let data = try? archive.data(for: entry) else { return false }
                return (try? data.write(to: target, options: .atomic)) != nil
            }.value
        }
        for item in added {
            let song = Song(title: item.title, kind: SongKind(rawValue: item.kindRaw) ?? .pdf, fileName: item.fileName, text: item.text, key: item.key, importedNote: item.importedNote)
            song.id = item.id; song.kindRaw = item.kindRaw; song.dateAdded = Date()
            song.autoscrollSeconds = item.autoscrollSeconds; song.colorTags = item.colorTags
            song.pdfZoom = item.pdfZoom; song.chordSize = item.chordSize; song.startKey = item.startKey
            song.searchText = item.searchText; song.drawerNote = item.drawerNote
            song.quizSongIDs = item.quizSongIDs ?? []
            context.insert(song)
        }
        for item in content.notes where addedIDs.contains(item.songID) {
            let note = SongNote(songID: item.songID, text: item.text, x: item.x, y: item.y, width: item.width, height: item.height, pinned: item.pinned, colorHex: item.colorHex)
            note.fixedFontSize = item.fixedFontSize; note.created = item.created
            context.insert(note)
        }
        for item in content.highlights where addedIDs.contains(item.songID) {
            context.insert(Highlight(songID: item.songID, colorHex: item.colorHex, x: item.x, y: item.y, width: item.width, height: item.height))
        }
        for item in content.strokes ?? [] where addedIDs.contains(item.songID) {
            let stroke = InkStroke(songID: item.songID, colorHex: item.colorHex, lineWidth: item.lineWidth, points: item.points)
            stroke.created = item.created
            context.insert(stroke)
        }
        for item in content.markers where addedIDs.contains(item.songID) {
            context.insert(JumpMarker(songID: item.songID, y: item.y, number: item.number))
        }
        for item in content.chords where addedIDs.contains(item.songID) {
            let chord = ChordStamp(songID: item.songID, root: item.root, quality: item.quality, bass: item.bass, x: item.x, y: item.y, groupID: item.groupID)
            chord.flats = item.flats
            context.insert(chord)
        }
        try context.save()
        return added.count
    }

    /// Ersätter hela biblioteket med säkerhetskopian.
    @MainActor
    static func restore(_ content: Content, archive: ZipArchive, context: ModelContext, colorCodes: ColorCodes, progress: TaskProgress) async throws {
        // Ta bort allt som finns nu.
        for song in try context.fetch(FetchDescriptor<Song>()) { SongFileStore.delete(song.fileName); context.delete(song) }
        for sound in try context.fetch(FetchDescriptor<SoundClip>()) { SongFileStore.delete(sound.fileName); context.delete(sound) }
        try context.delete(model: Setlist.self)
        try context.delete(model: SongNote.self)
        try context.delete(model: Highlight.self)
        try context.delete(model: InkStroke.self)
        try context.delete(model: JumpMarker.self)
        try context.delete(model: ChordStamp.self)
        try context.delete(model: GigLog.self)

        let files = Set(content.songs.map(\.fileName) + content.sounds.map(\.fileName)).filter { !$0.isEmpty }
        progress.start("Läser in säkerhetskopia", total: files.count)
        defer { progress.finish() }
        for name in files {
            progress.currentName = name
            let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
                guard let entry = archive.entry(named: "files/" + name), let data = try? archive.data(for: entry) else { return false }
                return (try? data.write(to: SongFileStore.url(for: name), options: .atomic)) != nil
            }.value
            _ = ok
            progress.done += 1
        }

        if !content.colorNames.isEmpty { colorCodes.names = ColorCodes.filled(content.colorNames) }
        for item in content.songs {
            let song = Song(title: item.title, kind: SongKind(rawValue: item.kindRaw) ?? .pdf, fileName: item.fileName, text: item.text, key: item.key, importedNote: item.importedNote)
            song.id = item.id; song.kindRaw = item.kindRaw; song.dateAdded = item.dateAdded
            song.lastPlayed = item.lastPlayed; song.playCount = item.playCount
            song.autoscrollSeconds = item.autoscrollSeconds; song.colorTags = item.colorTags
            song.pdfZoom = item.pdfZoom; song.chordSize = item.chordSize; song.startKey = item.startKey
            song.searchText = item.searchText; song.drawerNote = item.drawerNote
            song.quizSongIDs = item.quizSongIDs ?? []
            context.insert(song)
        }
        for item in content.setlists {
            let list = Setlist(name: item.name, songIDs: item.songIDs, setBreaks: item.setBreaks)
            list.id = item.id; list.created = item.created
            context.insert(list)
        }
        for item in content.notes {
            let note = SongNote(songID: item.songID, text: item.text, x: item.x, y: item.y, width: item.width, height: item.height, pinned: item.pinned, colorHex: item.colorHex)
            note.id = item.id; note.fixedFontSize = item.fixedFontSize; note.created = item.created
            context.insert(note)
        }
        for item in content.highlights {
            let highlight = Highlight(songID: item.songID, colorHex: item.colorHex, x: item.x, y: item.y, width: item.width, height: item.height)
            highlight.id = item.id
            context.insert(highlight)
        }
        for item in content.strokes ?? [] {
            let stroke = InkStroke(songID: item.songID, colorHex: item.colorHex, lineWidth: item.lineWidth, points: item.points)
            stroke.id = item.id; stroke.created = item.created
            context.insert(stroke)
        }
        for item in content.markers {
            let marker = JumpMarker(songID: item.songID, y: item.y, number: item.number)
            marker.id = item.id
            context.insert(marker)
        }
        for item in content.chords {
            let chord = ChordStamp(songID: item.songID, root: item.root, quality: item.quality, bass: item.bass, x: item.x, y: item.y, groupID: item.groupID)
            chord.id = item.id; chord.flats = item.flats
            context.insert(chord)
        }
        for item in content.sounds {
            let sound = SoundClip(name: item.name, fileName: item.fileName, order: item.order, colorHex: item.colorHex)
            sound.id = item.id; sound.trimStart = item.trimStart; sound.trimEnd = item.trimEnd; sound.volumeDB = item.volumeDB
            context.insert(sound)
        }
        for item in content.logs {
            let log = GigLog(started: item.started)
            log.id = item.id; log.name = item.name; log.entries = item.entries
            context.insert(log)
        }
        try context.save()
    }
}
