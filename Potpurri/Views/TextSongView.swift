import SwiftUI

/// Visar en textlåt med ackorden ovanför texten, eller en anteckning som vanlig text.
struct TextSongView: View {
    let song: Song

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if song.kind == .note {
                    Text(song.text ?? "")
                        .font(.system(size: 20))
                        .textSelection(.enabled)
                } else {
                    if let key = song.key {
                        Text("Tonart: \(key)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 16)
                    }
                    ForEach(Array(ChordProText.parse(song.text ?? "", title: song.title).enumerated()), id: \.offset) { _, line in
                        switch line {
                        case .heading(let heading):
                            Text(heading.uppercased())
                                .font(.system(size: 15, weight: .semibold))
                                .tracking(1)
                                .foregroundStyle(.secondary)
                                .padding(.top, 14)
                                .padding(.bottom, 4)
                        case .lyric(let chords, let text):
                            VStack(alignment: .leading, spacing: 0) {
                                if let chords, !chords.isEmpty {
                                    Text(chords)
                                        .fontWeight(.bold)
                                }
                                if !text.isEmpty {
                                    Text(text)
                                }
                            }
                            .font(.system(size: 22, design: .monospaced))
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
