import SwiftData
import SwiftUI

/// Kopplar låtens lappar och markeringar (SwiftData) till lagret i låtbladet.
/// Osynlig vy som bara håller lagret uppdaterat och sparar ändringar.
struct AnnotationSync: View {
    let song: Song
    let overlay: AnnotationOverlay

    @Environment(\.modelContext) private var context
    @Environment(Player.self) private var player
    @Query private var notes: [SongNote]
    @Query private var highlights: [Highlight]

    init(song: Song, overlay: AnnotationOverlay) {
        self.song = song
        self.overlay = overlay
        let id = song.id
        _notes = Query(filter: #Predicate<SongNote> { $0.songID == id && !$0.pinned }, sort: \SongNote.created)
        _highlights = Query(filter: #Predicate<Highlight> { $0.songID == id })
    }

    private var noteItems: [AnnotationOverlay.NoteItem] {
        notes.map { .init(id: $0.id, text: $0.text, colorHex: $0.colorHex, x: $0.x, y: $0.y, width: $0.width, height: $0.height, fontSize: $0.fixedFontSize) }
    }

    private var highlightItems: [AnnotationOverlay.HighlightItem] {
        highlights.map { .init(id: $0.id, colorHex: $0.colorHex, x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
    }

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onAppear {
                connect()
                importOnSongNote()
                push()
            }
            .onChange(of: noteItems) { push() }
            .onChange(of: highlightItems) { push() }
            .onChange(of: player.pen) { push() }
            .onChange(of: player.notesHidden) { push() }
            .onChange(of: player.isLocked) { push() }
    }

    private func push() {
        overlay.update(notes: noteItems, highlights: highlightItems, notesHidden: player.notesHidden, locked: player.isLocked, pen: player.isLocked ? .off : player.pen)
    }

    /// Lagret anropar tillbaka när något ändrats. Lappen hämtas på nytt varje gång,
    /// så att även lappar som skapats efter att låten öppnades hittas.
    private func connect() {
        let songID = song.id
        let context = context
        func note(_ id: UUID) -> SongNote? {
            try? context.fetch(FetchDescriptor<SongNote>(predicate: #Predicate { $0.id == id })).first
        }
        overlay.onMoveNote = { id, x, y in
            if let note = note(id) { note.x = x; note.y = y }
        }
        overlay.onResizeNote = { id, width, height in
            if let note = note(id) { note.width = width; note.height = height }
        }
        overlay.onTapNote = { id in player.editingNoteID = id }
        overlay.onAddHighlight = { hex, x, y, width, height in
            context.insert(Highlight(songID: songID, colorHex: hex, x: x, y: y, width: width, height: height))
        }
        overlay.onEraseHighlight = { id in
            if let highlight = try? context.fetch(FetchDescriptor<Highlight>(predicate: #Predicate { $0.id == id })).first {
                context.delete(highlight)
            }
        }
    }

    /// Anteckningar som följde med från OnSong blir en gul lapp första gången låten öppnas.
    private func importOnSongNote() {
        guard let text = song.importedNote, !text.isEmpty else { return }
        context.insert(SongNote(songID: song.id, text: text, x: 0.6, y: 0.02, width: 0.34, height: 0.12))
        song.importedNote = nil
    }
}

/// Lappar som sitter fast på skärmen: ligger still ovanpå låten medan den scrollar.
struct PinnedNotesLayer: View {
    let song: Song
    @Environment(Player.self) private var player
    @Query private var notes: [SongNote]

    init(song: Song) {
        self.song = song
        let id = song.id
        _notes = Query(filter: #Predicate<SongNote> { $0.songID == id && $0.pinned }, sort: \SongNote.created)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.allowsHitTesting(false)
            if !player.notesHidden {
                ForEach(notes) { note in
                    PinnedNoteView(note: note, editable: !player.isLocked) {
                        player.editingNoteID = note.id
                    }
                }
            }
        }
    }
}

private struct PinnedNoteView: View {
    @Bindable var note: SongNote
    let editable: Bool
    let onTap: () -> Void
    @State private var dragStart: CGPoint?
    @State private var sizeStart: CGSize?

    var body: some View {
        Text(note.text)
            .font(.system(size: note.fixedFontSize ?? 80, weight: .semibold))
            .minimumScaleFactor(note.fixedFontSize == nil ? 0.05 : 1)
            .multilineTextAlignment(.center)
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: note.width, height: note.height)
            .background(Color(uiColor: UIColor(hex: note.colorHex)), in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .topLeading) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.black.opacity(0.5))
                    .padding(5)
            }
            .overlay(alignment: .bottomTrailing) {
                if editable {
                    Image(systemName: "arrow.down.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black.opacity(0.45))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(coordinateSpace: .global)
                                .onChanged { value in
                                    let start = sizeStart ?? CGSize(width: note.width, height: note.height)
                                    sizeStart = start
                                    note.width = max(70, start.width + value.translation.width)
                                    note.height = max(44, start.height + value.translation.height)
                                }
                                .onEnded { _ in sizeStart = nil }
                        )
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        guard editable else { return }
                        let start = dragStart ?? CGPoint(x: note.x, y: note.y)
                        dragStart = start
                        note.x = max(0, start.x + value.translation.width)
                        note.y = max(0, start.y + value.translation.height)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture {
                if editable { onTap() }
            }
            // Positionen sist, så att bara lappen (inte hela skärmen) tar emot fingret.
            .position(x: note.x + note.width / 2, y: note.y + note.height / 2)
            .accessibilityLabel("Lapp fast på skärmen: \(note.text)")
            .accessibilityHint("Tryck för att redigera")
    }
}

/// Redigera en lapp: text, färg, förankring och "Ta bort".
struct NoteEditor: View {
    @Bindable var note: SongNote
    let unit: CGFloat
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    TextEditor(text: $note.text)
                        .font(.title3)
                        .frame(minHeight: 140)
                        .focused($focused)
                }
                Section("Färg") {
                    HStack(spacing: 14) {
                        ForEach(NoteColors.notes, id: \.self) { hex in
                            Button {
                                note.colorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(uiColor: UIColor(hex: hex)))
                                    .frame(width: 40, height: 40)
                                    .overlay(Circle().stroke(note.colorHex == hex ? Color.primary : Color.secondary.opacity(0.3), lineWidth: note.colorHex == hex ? 3 : 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Färg")
                            .accessibilityAddTraits(note.colorHex == hex ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Textstorlek") {
                    Toggle("Anpassa texten efter lappen", isOn: Binding(
                        get: { note.fixedFontSize == nil },
                        set: { auto in note.fixedFontSize = auto ? nil : toStored(24) }
                    ))
                    if let stored = note.fixedFontSize {
                        HStack(spacing: 14) {
                            Image(systemName: "textformat.size.smaller")
                            Slider(value: Binding(get: { fromStored(stored) }, set: { note.fixedFontSize = toStored($0) }), in: 10...72, step: 1)
                            Image(systemName: "textformat.size.larger")
                            Text("\(Int(fromStored(stored).rounded())) pt")
                                .monospacedDigit()
                                .frame(width: 52, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Textstorlek")
                    }
                }
                Section("Förankring") {
                    Picker("Förankring", selection: Binding(get: { note.pinned }, set: setPinned)) {
                        Text("Följer sidan").tag(false)
                        Text("Fast på skärmen").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button("Ta bort lappen", role: .destructive) {
                        context.delete(note)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Lapp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") { dismiss() }
                }
            }
            .onAppear { focused = note.text.isEmpty || note.text == "Ny lapp" }
        }
    }

    /// Textstorlek i punkter ↔ det som sparas (andel av bladets bredd för lappar som följer sidan).
    private func toStored(_ points: Double) -> Double {
        note.pinned || unit <= 0 ? points : points / Double(unit)
    }

    private func fromStored(_ stored: Double) -> Double {
        note.pinned || unit <= 0 ? stored : stored * Double(unit)
    }

    /// Byte mellan "följer sidan" (andel av bladets bredd) och "fast på skärmen" (punkter).
    private func setPinned(_ pinned: Bool) {
        guard pinned != note.pinned, unit > 0 else { return }
        let points = note.fixedFontSize.map(fromStored)
        if pinned {
            note.x = 40; note.y = 80
            note.width *= unit; note.height *= unit
        } else {
            note.width /= unit; note.height /= unit
            note.x = 0.1; note.y = 0.05
        }
        note.pinned = pinned
        note.fixedFontSize = points.map(toStored)
    }
}

/// Knappen "Penna på · Stäng av" med pennfärger och sudd.
struct PenBar: View {
    @Environment(Player.self) private var player

    var body: some View {
        HStack(spacing: 10) {
            ForEach(NoteColors.pens, id: \.self) { hex in
                Button {
                    player.pen = .color(hex)
                } label: {
                    Capsule()
                        .fill(Color(uiColor: UIColor(hex: hex)))
                        .frame(width: 34, height: 22)
                        .overlay(Capsule().stroke(player.pen == .color(hex) ? Color.primary : .clear, lineWidth: 3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pennfärg")
                .accessibilityAddTraits(player.pen == .color(hex) ? .isSelected : [])
            }
            Button {
                player.pen = .eraser
            } label: {
                Image(systemName: "eraser")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 40, height: 36)
                    .background(player.pen == .eraser ? Color.accentColor.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sudd")
            Button {
                player.pen = .off
            } label: {
                Text("Penna på · Stäng av")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}
