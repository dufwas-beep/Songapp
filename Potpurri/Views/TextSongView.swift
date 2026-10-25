import SwiftUI

/// Visar en textlåt med ackorden ovanför texten, eller en anteckning som vanlig text.
struct TextSongView: View {
    let song: Song

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if song.kind == .note {
                    ForEach(Array(NoteText.parse(song.text ?? "").enumerated()), id: \.offset) { _, line in
                        NoteLineView(line: line)
                    }
                } else {
                    // Samma upplägg som låtbladen: titel, tonart, rubriker i versaler och ackord i fetstil.
                    Text(song.title)
                        .font(.system(size: 34, weight: .semibold))
                    if let key = song.key {
                        Text("Tonart: \(key)")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    Color.clear.frame(height: 20)
                    ForEach(Array(ChordProText.parse(song.text ?? "", title: song.title).enumerated()), id: \.offset) { _, line in
                        switch line {
                        case .heading(let heading):
                            Text(heading.uppercased())
                                .font(.system(size: 16, weight: .semibold))
                                .tracking(1.5)
                                .foregroundStyle(.secondary)
                                .padding(.top, 16)
                                .padding(.bottom, 6)
                        case .lyric(let segments):
                            LyricLineView(segments: segments)
                        case .blank:
                            Color.clear.frame(height: 14)
                        }
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// En textrad med ackorden ovanför orden de hör till.
private struct LyricLineView: View {
    let segments: [ChordProText.Segment]

    private var hasChords: Bool {
        segments.contains { $0.chord != nil }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                VStack(alignment: .leading, spacing: 0) {
                    if hasChords {
                        // Ett mellanslag efter ackordet så att två ackord i rad inte krockar.
                        Text(Self.keepSpaces(segment.chord.map { $0 + " " } ?? " "))
                            .font(.system(size: 22, weight: .bold))
                    }
                    Text(Self.keepSpaces(segment.text.isEmpty ? " " : segment.text))
                        .font(.system(size: 24))
                }
                .fixedSize()
            }
        }
        .padding(.vertical, 2)
    }

    /// Hårda mellanslag, så att mellanrummet i slutet av en bit inte försvinner.
    private static func keepSpaces(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: "\u{00A0}")
    }
}

/// En rad i ett quizmanus: rubriker stora och feta, svar rosa och feta, låtrader nedtonade.
private struct NoteLineView: View {
    let line: NoteText.Line

    var body: some View {
        switch line.style {
        case .heading:
            Text(line.text)
                .font(.system(size: 26, weight: .bold))
                .padding(.top, 18)
                .padding(.bottom, 4)
        case .question, .normal:
            Text(line.text)
                .font(.system(size: 22))
                .padding(.vertical, 2)
        case .answer:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                Text(line.text)
            }
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(Color.accentColor)
            .padding(.leading, 24)
            .padding(.vertical, 2)
        case .muted:
            Text(line.text)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
        case .blank:
            Color.clear.frame(height: 12)
        }
    }
}
