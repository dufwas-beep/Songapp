import SwiftData
import SwiftUI

/// Låtarna som hör till ett quiz (t.ex. "HLS 45"), i ordning. Tryck = visa låten,
/// håll in = ta bort ur quizet, håll in och dra = flytta (en rosa linje visar var).
/// "Lägg till låtar" väljer fler ur biblioteket; en låt kan också dras hit från listorna.
struct QuizSongsList: View {
    let quiz: Song
    let onOpen: (Song) -> Void
    @Query private var songs: [Song]
    @Environment(Player.self) private var player
    @Environment(\.modelContext) private var context
    @State private var adding = false
    @State private var dropTarget: Int?

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
                    .draggable("quizsong:\(index)") {
                        Text(song.title)
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .overlay(alignment: .top) {
                        if dropTarget == index { DropLine() }
                    }
                    .dropDestination(for: String.self) { items, _ in
                        drop(items, before: index)
                    } isTargeted: { target(index, $0) }
                }
            }
            if !quiz.quizSongIDs.isEmpty {
                // Släpp här = sist i quizet.
                let end = quiz.quizSongIDs.count
                Color.clear
                    .frame(height: 14)
                    .contentShape(Rectangle())
                    .overlay(alignment: .top) {
                        if dropTarget == end { DropLine() }
                    }
                    .dropDestination(for: String.self) { items, _ in
                        drop(items, before: end)
                    } isTargeted: { target(end, $0) }
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

    private func target(_ index: Int, _ targeted: Bool) {
        if targeted {
            dropTarget = index
        } else if dropTarget == index {
            dropTarget = nil
        }
    }

    /// En låt i quizet flyttas, eller en låt från listorna läggs till, före `index`.
    private func drop(_ items: [String], before index: Int) -> Bool {
        dropTarget = nil
        guard !player.isLocked, let item = items.first else { return false }
        var ids = quiz.quizSongIDs
        if item.hasPrefix("quizsong:"), let from = Int(item.dropFirst(9)), ids.indices.contains(from) {
            guard from != index, from + 1 != index else { return true }
            let id = ids.remove(at: from)
            ids.insert(id, at: from < index ? index - 1 : index)
        } else if item.hasPrefix("song:"), let id = UUID(uuidString: String(item.dropFirst(5))) {
            ids.insert(id, at: min(index, ids.count))
        } else {
            return false
        }
        withAnimation(.easeOut(duration: 0.2)) {
            quiz.quizSongIDs = ids
        }
        try? context.save()
        return true
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

    /// Ungefär så hög som listan är, men högst 340 punkter (sedan scrollar den).
    private var listHeight: CGFloat {
        let rows = CGFloat(max(quiz.quizSongIDs.count, 1)) * 37
        return min(340, rows + (player.isLocked ? 8 : 46))
    }

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
                .frame(height: listHeight)
            }
        }
        .frame(width: open ? 300 : 230)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}
