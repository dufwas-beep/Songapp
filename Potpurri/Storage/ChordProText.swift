import Foundation

/// Tolkar låttext i OnSong-/ChordPro-format: ackord i hakparenteser ("Jag [G]går") blir
/// en egen ackordrad ovanför texten, och rader som "Vers 1:" blir rubriker.
enum ChordProText {
    enum Line: Hashable {
        case heading(String)
        case lyric(chords: String?, text: String)
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
        for raw in text.components(separatedBy: .newlines) {
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

    /// Flyttar ackorden ur texten till en egen rad, på samma position som i texten.
    private static func lyricLine(_ raw: String) -> Line {
        guard raw.contains("[") else { return .lyric(chords: nil, text: raw) }
        var chords = ""
        var text = ""
        var chord: String?
        for character in raw {
            if character == "[" {
                chord = ""
            } else if character == "]", let current = chord {
                // Ackordet hamnar ovanför nästa bokstav; krockar det med föregående ackord flyttas texten.
                if chords.count > text.count {
                    text += String(repeating: " ", count: chords.count - text.count)
                }
                chords += String(repeating: " ", count: text.count - chords.count) + current + " "
                chord = nil
            } else if chord != nil {
                chord?.append(character)
            } else {
                text.append(character)
            }
        }
        let trimmedChords = chords.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        let trimmedText = text.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        return .lyric(chords: trimmedChords, text: trimmedText)
    }
}
