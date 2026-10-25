import Foundation

/// Tolkar låttext i OnSong-/ChordPro-format: ackord i hakparenteser ("Jag [G]går") hamnar
/// ovanför ordet de står vid, och rader som "Vers 1:" blir rubriker.
enum ChordProText {
    /// En bit av en textrad: ackordet (om något) och texten under det.
    struct Segment: Hashable {
        let chord: String?
        let text: String
    }

    enum Line: Hashable {
        case heading(String)
        case lyric([Segment])
        case blank
    }

    private static let metadataKeys: Set<String> = [
        "title", "artist", "author", "key", "capo", "tempo", "time", "duration", "ccli",
        "copyright", "book", "number", "flow", "keywords", "topic", "album", "year",
        "ordered by", "subtitle", "byline", "midi", "transpose"
    ]

    /// "Key: G" → ("key", "G"). Annat → nil.
    static func metadata(in line: String) -> (key: String, value: String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard metadataKeys.contains(key), !value.isEmpty else { return nil }
        return (key, value)
    }

    static func parse(_ text: String, title: String) -> [Line] {
        var result: [Line] = []
        var isFirst = true
        for raw in mergeChordLines(text.components(separatedBy: .newlines)) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            defer { isFirst = false }
            if line.isEmpty {
                if result.last != .blank && !result.isEmpty { result.append(.blank) }
                continue
            }
            // Första raden är låtens titel, och uppgifter som "Artist: …" visas inte.
            if isFirst && line == title { continue }
            if metadata(in: line) != nil { continue }

            // ChordPro-direktiv: {title: …} hoppas över, {comment: …} och {c: …} blir rubriker.
            if line.hasPrefix("{") && line.hasSuffix("}") {
                let inner = String(line.dropFirst().dropLast())
                let parts = inner.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2, ["c", "comment", "ci", "cb"].contains(parts[0].lowercased()) {
                    result.append(.heading(parts[1]))
                }
                continue
            }
            if line.hasSuffix(":") && !line.contains("[") && line.count <= 30 {
                result.append(.heading(String(line.dropLast())))
                continue
            }
            result.append(lyricLine(raw))
        }
        while result.last == .blank { result.removeLast() }
        return result
    }

    private static let chordPattern = "^[A-H][#b♯♭]?(m|maj|min|dim|aug|sus|add|M)?[0-9]*(sus[0-9]*|add[0-9]*|b[0-9]+|#[0-9]+)*(/[A-H][#b♯♭]?)?$"

    /// En rad som bara består av ackord, t.ex. "G      D    Em".
    private static func isChordLine(_ line: String) -> Bool {
        let tokens = line.split(separator: " ").map(String.init).filter { $0 != "|" && $0 != "-" }
        return !tokens.isEmpty && tokens.allSatisfy { $0.range(of: chordPattern, options: .regularExpression) != nil }
    }

    /// Ackord skrivna på en egen rad ovanför texten görs om till ackord i texten
    /// ("[G]Jag går [D]hem"), så att de hamnar rätt även med ett vanligt typsnitt.
    private static func mergeChordLines(_ lines: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index].replacingOccurrences(of: "\t", with: "    ")
            guard isChordLine(line) else {
                result.append(lines[index])
                index += 1
                continue
            }
            // Ackordens kolumner i raden.
            var chords: [(column: Int, name: String)] = []
            var column = 0
            for token in line.split(separator: " ", omittingEmptySubsequences: false) {
                if !token.isEmpty { chords.append((column, String(token))) }
                column += token.count + 1
            }
            let next = index + 1 < lines.count ? lines[index + 1] : ""
            let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
            if !nextTrimmed.isEmpty, !isChordLine(next), !nextTrimmed.hasSuffix(":"), !next.contains("[") {
                var text = Array(next.replacingOccurrences(of: "\t", with: "    "))
                if let last = chords.last, text.count < last.column {
                    text += Array(repeating: " ", count: last.column - text.count)
                }
                // Infoga bakifrån så att kolumnerna stämmer.
                for chord in chords.reversed() {
                    text.insert(contentsOf: Array("[\(chord.name)]"), at: min(chord.column, text.count))
                }
                result.append(String(text))
                index += 2
            } else {
                result.append(chords.map { "[\($0.name)] " }.joined())
                index += 1
            }
        }
        return result
    }

    /// Delar raden vid varje ackord, så att ackordet kan ritas ovanför rätt ord
    /// även med ett vanligt (inte jämnbrett) typsnitt.
    private static func lyricLine(_ raw: String) -> Line {
        var segments: [Segment] = []
        var chord: String?
        var text = ""
        var readingChord: String?
        for character in raw {
            if character == "[" {
                readingChord = ""
            } else if character == "]", let finished = readingChord {
                if chord != nil || !text.isEmpty {
                    segments.append(Segment(chord: chord, text: text))
                }
                chord = finished
                text = ""
                readingChord = nil
            } else if readingChord != nil {
                readingChord?.append(character)
            } else {
                text.append(character)
            }
        }
        if chord != nil || !text.isEmpty {
            segments.append(Segment(chord: chord, text: text))
        }
        return .lyric(segments)
    }
}
