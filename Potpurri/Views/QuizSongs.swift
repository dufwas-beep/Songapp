import SwiftData
import SwiftUI

/// Låtarna som hör till ett quiz (t.ex. "HLS 45"), i ordning. Tryck = visa låten,
/// håll in = ta bort ur quizet. "Lägg till låtar" väljer fler ur biblioteket.
struct QuizSongsList: View {
    let quiz: Song
    let onOpen: (Song) -> Void
    @Query private var songs: [Song]
    @Environment(Player.self) private var player
    @Environment(\.modelContext) private var context
    @State private var adding = false

    var body: some View {
        let byID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        VStack(alignment: .leading, spacing: 0) {
            if quiz.quizSongIDs.isEmpty {
                Text("Inga låtar i quizet än.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            ForEach(Array(quiz.quizSongIDs.enumerated()), id: \.offset) { index, id in
                if let song = byID[id] {
                    Button {
                        onOpen(song)
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.callout)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 22, alignment: .trailing)
                            Text(song.title)
                                .lineLimit(1)
                                .foregroundStyle(player.isPlayedTonight(song) ? .secondary : .primary)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if !player.isLocked {
                            Button(role: .destructive) {
                                remove(at: index)
                            } label: {
                                Label("Ta bort ur quizet", systemImage: "minus.circle")
                            }
                        }
                    }
                }
            }
            if !player.isLocked {
                Button {
                    adding = true
                } label: {
                    Label("Lägg till låtar", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderless)
                .padding(.vertical, 8)
            }
        }
        .sheet(isPresented: $adding) {
            AddSongsSheet(title: "Låtar till \(quiz.title)", existing: quiz.quizSongIDs) { ids in
                quiz.quizSongIDs.append(contentsOf: ids)
                try? context.save()
            }
        }
    }

    private func remove(at index: Int) {
        var ids = quiz.quizSongIDs
        guard ids.indices.contains(index) else { return }
        ids.remove(at: index)
        quiz.quizSongIDs = ids
        try? context.save()
    }
}

/// Inne i ett quiz: rutan uppe till vänster med quizets låtar. Tryck på rubriken för
/// att fälla ihop den. En låt man trycker på visas i förhandsrutan under quizet.
struct QuizPanel: View {
    let quiz: Song
    @AppStorage("quizPanelOpen") private var open = true
    @Environment(Player.self) private var player

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .foregroundStyle(Color.accentColor)
                    Text("Låtar i quizet")
                        .font(.subheadline.weight(.semibold))
                    Text("\(quiz.quizSongIDs.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? "Fäll ihop låtarna i quizet" : "Visa låtarna i quizet")
            if open {
                Divider()
                ScrollView {
                    QuizSongsList(quiz: quiz) { song in
                        player.previewID = song.id
                    }
                    .padding(.horizontal, 14)
                }
                .frame(maxHeight: 340)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: open ? 300 : 230)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}
