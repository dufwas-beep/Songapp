import SwiftUI

/// Visar en textlåt med ackorden ovanför texten, eller en anteckning (t.ex. ett quizmanus).
/// Raderna bryts så att allt alltid syns, och textstorleken följer hur bred vyn är –
/// större när biblioteket är stängt, mindre när det är öppet.
struct TextSongView: View {
    let song: Song

    /// Textlåtar utan ackord (t.ex. quizmanus skrivna i OnSong) visas som anteckningar.
    private var showsAsNote: Bool {
        song.kind == .note || !ChordProText.hasChords(song.text ?? "")
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(max(geometry.size.width / 820, 0.8), 1.3)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if showsAsNote {
                        ForEach(Array(NoteText.parse(song.text ?? "").enumerated()), id: \.offset) { _, line in
                            NoteLineView(line: line, scale: scale)
                        }
                    } else {
                        songBody(scale: scale)
                    }
                }
                .padding(.horizontal, 48 * min(scale, 1))
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Samma upplägg som låtbladen: titel, tonart, rubriker i versaler och ackord i fetstil.
    @ViewBuilder
    private func songBody(scale: CGFloat) -> some View {
        Text(song.title)
            .font(.system(size: 34 * scale, weight: .semibold))
        if let key = song.key {
            Text("Tonart: \(key)")
                .font(.system(size: 18 * scale))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        Color.clear.frame(height: 20)
        ForEach(Array(ChordProText.parse(song.text ?? "", title: song.title).enumerated()), id: \.offset) { _, line in
            switch line {
            case .heading(let heading):
                Text(heading.uppercased())
                    .font(.system(size: 16 * scale, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
                    .padding(.bottom, 6)
            case .lyric(let segments):
                LyricLineView(segments: segments, scale: scale)
            case .blank:
                Color.clear.frame(height: 14 * scale)
            }
        }
    }
}

/// En textrad med ackorden ovanför orden de hör till. Raden bryts mellan orden när
/// den inte får plats, och ackorden följer med sitt ord.
private struct LyricLineView: View {
    let segments: [ChordProText.Segment]
    let scale: CGFloat

    private var hasChords: Bool {
        segments.contains { $0.chord != nil }
    }

    /// Varje bit delas i ord; ackordet hör till första ordet i biten.
    private var words: [ChordProText.Segment] {
        segments.flatMap { segment -> [ChordProText.Segment] in
            var parts = segment.text.components(separatedBy: " ")
            for index in parts.indices.dropLast() {
                parts[index] += " "
            }
            parts = parts.filter { !$0.isEmpty }
            if parts.isEmpty { parts = [""] }
            return parts.enumerated().map { index, word in
                ChordProText.Segment(chord: index == 0 ? segment.chord : nil, text: word)
            }
        }
    }

    var body: some View {
        FlowLayout {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                VStack(alignment: .leading, spacing: 0) {
                    if hasChords {
                        // Ett mellanslag efter ackordet så att två ackord i rad inte krockar.
                        Text(Self.keepSpaces(word.chord.map { $0 + " " } ?? " "))
                            .font(.system(size: 22 * scale, weight: .bold))
                    }
                    Text(Self.keepSpaces(word.text.isEmpty ? " " : word.text))
                        .font(.system(size: 24 * scale))
                }
                .fixedSize()
            }
        }
        .padding(.vertical, 2)
    }

    /// Hårda mellanslag, så att mellanrummet efter ett ord inte försvinner.
    private static func keepSpaces(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: "\u{00A0}")
    }
}

/// Lägger bitarna efter varandra och fortsätter på nästa rad när bredden tar slut.
private struct FlowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.maxX, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews, width: bounds.width)
        for (subview, point) in zip(subviews, rows.points) {
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (points: [CGPoint], maxX: CGFloat, height: CGFloat) {
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x)
        }
        return (points, maxX, y + rowHeight)
    }
}

/// En rad i ett quizmanus: rubriker stora och feta, svar rosa och feta, låtrader nedtonade.
private struct NoteLineView: View {
    let line: NoteText.Line
    let scale: CGFloat

    var body: some View {
        switch line.style {
        case .heading:
            Text(line.text)
                .font(.system(size: 26 * scale, weight: .bold))
                .padding(.top, 18)
                .padding(.bottom, 4)
        case .question, .normal:
            Text(line.text)
                .font(.system(size: 22 * scale))
                .padding(.vertical, 2)
        case .answer:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                Text(line.text)
            }
            .font(.system(size: 22 * scale, weight: .bold))
            .foregroundStyle(Color.accentColor)
            .padding(.leading, 24)
            .padding(.vertical, 2)
        case .muted:
            Text(line.text)
                .font(.system(size: 18 * scale))
                .foregroundStyle(.secondary)
        case .blank:
            Color.clear.frame(height: 12 * scale)
        }
    }
}
