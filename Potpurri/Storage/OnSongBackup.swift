import Foundation

/// En låt i en OnSong-backup som kan importeras.
struct OnSongCandidate: Identifiable {
    enum Content {
        /// En fil i arkivet (PDF, bild eller .txt-anteckning).
        case file(entryName: String)
        /// Text med ackord som skrivits direkt i OnSong.
        case text(String)
    }

    let id: String
    let title: String
    let kind: SongKind
    let content: Content
    let key: String?
    let note: String?
    /// En låt med samma namn finns redan i Potpurri.
    let alreadyExists: Bool
}

/// En låtlista i OnSong: låtarnas OnSong-id i ordning, och var nya set börjar.
struct OnSongSetlist {
    let name: String
    let songIDs: [String]
    let setBreaks: [Int]
}

/// En inläst OnSong-backup, redo att visas i importlistan.
struct OnSongBackup: Identifiable {
    let id = UUID()
    /// Tillfällig mapp med kopian av backupen; tas bort när importen är klar.
    let workDirectory: URL
    let archive: ZipArchive
    let candidates: [OnSongCandidate]
    let setlists: [OnSongSetlist]

    func cleanUp() {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    /// Kopierar backupen till en tillfällig mapp. Ligger den i Dropbox/iCloud laddas den ner först.
    static func copyToWorkDirectory(_ url: URL) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OnSongImport-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let local = directory.appendingPathComponent("OnSong.backup")

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        var copyError: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { readURL in
            do {
                try FileManager.default.copyItem(at: readURL, to: local)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError { throw error }
        return local
    }

    /// Läser OnSongs databas och listar låtar och låtlistor.
    static func read(localBackup: URL, existingTitles: Set<String>) throws -> OnSongBackup {
        let archive = try ZipArchive(url: localBackup)
        guard let databaseEntry = archive.entry(named: "OnSong.sqlite3") else {
            throw SQLiteReader.Failure(message: "Hittade ingen OnSong-databas i filen. Är det en OnSong-backup?")
        }
        let databaseURL = localBackup.deletingLastPathComponent().appendingPathComponent("OnSong.sqlite3")
        try archive.data(for: databaseEntry).write(to: databaseURL)
        let db = try SQLiteReader(url: databaseURL)

        var candidates: [OnSongCandidate] = []
        for row in try db.rows("SELECT * FROM Song") {
            // Låtar som tagits bort i OnSong och OnSongs egen välkomstlåt hoppas över.
            guard let id = row["ID"], id != "welcome_to_onsong", row["deleted"] != "1" else { continue }
            let title = (row["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            var kind: SongKind?
            var content: OnSongCandidate.Content?
            if row["usefile"] == "1", let fileName = [row["filename"], row["filepath"]].compactMap({ $0 }).first(where: { !$0.isEmpty }), let entry = archive.entry(named: fileName) {
                kind = Self.kind(forFileName: entry.name)
                content = .file(entryName: entry.name)
            }
            if kind == nil, let text = row["content"], Self.hasLyrics(text, title: title) {
                kind = .text
                content = .text(text)
            }
            guard let kind, let content else { continue }

            candidates.append(OnSongCandidate(
                id: id,
                title: title,
                kind: kind,
                content: content,
                key: row["key"].flatMap { $0.isEmpty ? nil : $0 },
                note: Self.noteText(from: row["notes"]),
                alreadyExists: existingTitles.contains(title.lowercased())
            ))
        }
        candidates.sort { $0.title.compare($1.title, options: [.caseInsensitive, .numeric], locale: Locale(identifier: "sv_SE")) == .orderedAscending }

        var setlists: [OnSongSetlist] = []
        let items = (try? db.rows("SELECT * FROM SongSetItem ORDER BY setID, orderIndex")) ?? []
        for set in (try? db.rows("SELECT * FROM SongSet ORDER BY orderIndex")) ?? [] {
            guard let setID = set["ID"], let name = set["title"], !name.isEmpty else { continue }
            var songIDs: [String] = []
            var breaks: [Int] = []
            for item in items where item["setID"] == setID {
                // En avdelare i listan betyder att ett nytt set börjar här.
                if let divider = item["divider"], divider != "0", !songIDs.isEmpty {
                    breaks.append(songIDs.count)
                }
                if let songID = item["songID"], !songID.isEmpty {
                    songIDs.append(songID)
                }
            }
            if !songIDs.isEmpty {
                setlists.append(OnSongSetlist(name: name, songIDs: songIDs, setBreaks: Array(Set(breaks)).sorted()))
            }
        }

        return OnSongBackup(workDirectory: localBackup.deletingLastPathComponent(), archive: archive, candidates: candidates, setlists: setlists)
    }

    static func kind(forFileName name: String) -> SongKind? {
        let lower = name.lowercased()
        // OnSong sparar en mörk kopia av varje PDF; Potpurri har eget mörkt läge.
        if lower.hasSuffix(".maintain.inverted.pdf") { return nil }
        switch (lower as NSString).pathExtension {
        case "pdf": return .pdf
        case "jpg", "jpeg", "png", "heic", "gif", "tif", "tiff": return .image
        case "txt": return .note
        default: return nil
        }
    }

    /// OnSong lägger låtens titel som första rad även när låten bara är en fil;
    /// det räknas inte som en textlåt.
    private static func hasLyrics(_ text: String, title: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != title && ChordProText.metadata(in: $0) == nil }
        return lines.count >= 2
    }

    /// OnSongs anteckningar ligger som JSON med lappar ("stickyNotes"), eller som vanlig text.
    static func noteText(from notes: String?) -> String? {
        guard let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty else { return nil }
        guard notes.hasPrefix("{") else { return notes }
        guard let data = notes.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stickies = json["stickyNotes"] as? [Any] else { return nil }
        let texts = stickies.compactMap { item -> String? in
            guard let dict = item as? [String: Any] else { return nil }
            let text = (dict["text"] ?? dict["content"] ?? dict["note"]) as? String
            return text?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        return texts.isEmpty ? nil : texts.joined(separator: "\n\n")
    }

    /// Textfilerna i backupen är ofta UTF-16 (quizmanus från Word), ibland UTF-8.
    static func decodeText(_ data: Data) -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16) ?? ""
        }
        if data.prefix(400).contains(0) {
            return String(data: data, encoding: .utf16LittleEndian) ?? ""
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }
}
