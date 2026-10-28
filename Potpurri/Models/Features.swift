import Foundation

/// Delar av appen som går att stänga av under kugghjulet (Funktioner), så att appen
/// blir så ren man vill. Allt är på från början.
enum Feature: String, CaseIterable, Identifiable {
    case next, quiz, spotify, soundboard, drawer, timer, record, pause, ideas
    case notes, pen, markers, chords

    var id: Self { self }

    /// Nyckeln i inställningarna (används med @AppStorage).
    var key: String { "feature." + rawValue }

    var title: String {
        switch self {
        case .next: "Next (förslag)"
        case .quiz: "Quiz-fliken"
        case .spotify: "Spotify"
        case .soundboard: "Soundboard"
        case .drawer: "Lådan"
        case .timer: "Timer"
        case .record: "Rec (filma)"
        case .pause: "Paus (skärmsläckare)"
        case .ideas: "Idélådan"
        case .notes: "Notes"
        case .pen: "Markeringspenna"
        case .markers: "Hopplinjer"
        case .chords: "Ackord"
        }
    }

    var symbol: String {
        switch self {
        case .next: "sparkles"
        case .quiz: "questionmark.bubble"
        case .spotify: "play.circle"
        case .soundboard: "speaker.wave.2"
        case .drawer: "tray"
        case .timer: "timer"
        case .record: "record.circle"
        case .pause: "cup.and.saucer"
        case .ideas: "lightbulb"
        case .notes: "note.text"
        case .pen: "highlighter"
        case .markers: "arrow.down.to.line"
        case .chords: "music.note"
        }
    }
}
