import Foundation
import SwiftData

/// Påhittade textlåtar för att prova hur appen klarar ett stort bibliotek.
enum TestSongs {
    static let prefix = "Testlåt "

    static func isTestSong(_ song: Song) -> Bool {
        song.title.hasPrefix(prefix) && song.kind == .text
    }

    static func add(_ count: Int, to context: ModelContext, existing: Int) {
        let keys = ["C", "G", "D", "A", "E", "F", "Bb", "Am", "Em", "Dm"]
        let progressions = [["C", "G", "Am", "F"], ["G", "D", "Em", "C"], ["Am", "F", "C", "G"], ["D", "A", "Bm", "G"]]
        let words = ["natten", "vägen", "hjärtat", "himlen", "staden", "havet", "dansen", "sommaren", "ljuset", "vinden"]
        for number in 1...count {
            let chords = progressions[number % progressions.count]
            var lines: [String] = []
            for verse in 1...4 {
                lines.append("Vers \(verse)")
                for line in 0..<4 {
                    let word = words[(number + verse + line) % words.count]
                    lines.append("[\(chords[line % 4])]Här går \(word) [\(chords[(line + 1) % 4])]genom kvällen, [\(chords[(line + 2) % 4])]sjung med i \(word)")
                }
                lines.append("")
            }
            let song = Song(
                title: prefix + String(format: "%03d", existing + number),
                kind: .text,
                text: lines.joined(separator: "\n"),
                key: keys[number % keys.count]
            )
            context.insert(song)
        }
        try? context.save()
    }
}
