import Foundation

/// Tonarter, stavning, diatoniska ackord och transponering för ackordstämplarna.
enum ChordTheory {
    static let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    static let flatNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
    /// Tonerna i C-skalan (för allt som inte finns bland tonartens ackord).
    static let naturals: [(name: String, pitch: Int)] = [("C", 0), ("D", 2), ("E", 4), ("F", 5), ("G", 7), ("A", 9), ("B", 11)]

    /// Vanligaste färgningarna först; resten under "Fler".
    static let commonQualities = ["", "m", "7", "m7", "maj7", "sus4", "sus2", "add9"]
    static let moreQualities = ["6", "m6", "9", "m9", "maj9", "7sus4", "dim", "dim7", "m7b5", "aug", "11", "13"]

    struct Key: Hashable {
        var root: Int
        var minor: Bool

        var name: String {
            ChordTheory.name(root, in: self) + (minor ? "m" : "")
        }

        /// Tonarter med b-förtecken stavas med b (Bb, Eb …), övriga med #.
        var usesFlats: Bool {
            let flatMajors: Set<Int> = [5, 10, 3, 8, 1, 6]     // F Bb Eb Ab Db Gb
            let flatMinors: Set<Int> = [2, 7, 0, 5, 10, 3]     // Dm Gm Cm Fm Bbm Ebm
            return minor ? flatMinors.contains(root) : flatMajors.contains(root)
        }
    }

    static func name(_ pitch: Int, in key: Key) -> String {
        let index = ((pitch % 12) + 12) % 12
        return key.usesFlats ? flatNames[index] : sharpNames[index]
    }

    /// Hela ackordnamnet, t.ex. "D/F#".
    static func label(root: Int, quality: String, bass: Int?, in key: Key) -> String {
        var text = name(root, in: key) + quality
        if let bass { text += "/" + name(bass, in: key) }
        return text
    }

    /// "G", "Am", "F#m", "Bb" → tonart. Okänt → C-dur.
    static func key(from text: String?) -> Key {
        guard var text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return Key(root: 0, minor: false) }
        var minor = false
        if text.hasSuffix("m") || text.lowercased().hasSuffix("moll") {
            minor = true
            text = text.lowercased().hasSuffix("moll") ? String(text.dropLast(4)).trimmingCharacters(in: .whitespaces) : String(text.dropLast())
        }
        if let pitch = pitch(of: text) { return Key(root: pitch, minor: minor) }
        return Key(root: 0, minor: false)
    }

    static func pitch(of name: String) -> Int? {
        if let index = sharpNames.firstIndex(of: name) { return index }
        if let index = flatNames.firstIndex(of: name) { return index }
        return nil
    }

    /// Tonartens ackord i ordning efter hur vanliga de är (i G: G C D Em Am Bm D7 F#dim).
    static func diatonicChords(in key: Key) -> [(root: Int, quality: String)] {
        let r = key.root
        if key.minor {
            // i, VI, VII, iv, III, v, V7, ii°
            return [(r, "m"), (r + 8, ""), (r + 10, ""), (r + 5, "m"), (r + 3, ""), (r + 7, "m"), (r + 7, "7"), (r + 2, "dim")]
                .map { ((($0.0 % 12) + 12) % 12, $0.1) }
        }
        // I, IV, V, vi, ii, iii, V7, vii°
        return [(r, ""), (r + 5, ""), (r + 7, ""), (r + 9, "m"), (r + 2, "m"), (r + 4, "m"), (r + 7, "7"), (r + 11, "dim")]
            .map { ((($0.0 % 12) + 12) % 12, $0.1) }
    }

    static let allKeys: [Key] = (0..<12).map { Key(root: $0, minor: false) } + (0..<12).map { Key(root: $0, minor: true) }
}
