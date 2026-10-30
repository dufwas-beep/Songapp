import SwiftData
import SwiftUI

/// Kopplar låtens markeringar (SwiftData) till pennlagret i låtbladet och gör om
/// anteckningar från OnSong till en note. Osynlig vy.
struct AnnotationSync: View {
    let song: Song
    let overlay: AnnotationOverlay

    @Environment(\.modelContext) private var context
    @Environment(Player.self) private var player
    @Query private var highlights: [Highlight]
    @Query private var strokes: [InkStroke]

    init(song: Song, overlay: AnnotationOverlay) {
        self.song = song
        self.overlay = overlay
        let id = song.id
        _highlights = Query(filter: #Predicate<Highlight> { $0.songID == id })
        _strokes = Query(filter: #Predicate<InkStroke> { $0.songID == id }, sort: \InkStroke.created)
    }

    private var highlightItems: [AnnotationOverlay.HighlightItem] {
        highlights.map { .init(id: $0.id, colorHex: $0.colorHex, x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
    }

    private var strokeItems: [AnnotationOverlay.StrokeItem] {
        strokes.map { .init(id: $0.id, colorHex: $0.colorHex, lineWidth: $0.lineWidth, points: $0.points) }
    }

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onAppear {
                connect()
                importOnSongNote()
                push()
            }
            .onChange(of: highlightItems) { push() }
            .onChange(of: strokeItems) { push() }
            .onChange(of: player.pen) { push() }
            .onChange(of: player.eraserSize) { push() }
            .onChange(of: player.isLocked) { push() }
    }

    private func push() {
        let radii = Player.eraserRadii
        overlay.update(
            highlights: highlightItems,
            strokes: strokeItems,
            pen: player.isLocked ? .off : player.pen,
            eraserRadius: radii[min(max(player.eraserSize, 0), radii.count - 1)]
        )
    }

    private func connect() {
        let songID = song.id
        let context = context
        overlay.onAddHighlight = { hex, x, y, width, height in
            context.insert(Highlight(songID: songID, colorHex: hex, x: x, y: y, width: width, height: height))
        }
        overlay.onEraseHighlight = { id in
            if let highlight = try? context.fetch(FetchDescriptor<Highlight>(predicate: #Predicate { $0.id == id })).first {
                context.delete(highlight)
            }
        }
        overlay.onAddStroke = { hex, width, points in
            context.insert(InkStroke(songID: songID, colorHex: hex, lineWidth: width, points: points))
        }
        overlay.onEraseStroke = { id in
            if let stroke = try? context.fetch(FetchDescriptor<InkStroke>(predicate: #Predicate { $0.id == id })).first {
                context.delete(stroke)
            }
        }
    }

    /// Anteckningar som följde med från OnSong blir en note första gången låten öppnas.
    private func importOnSongNote() {
        guard let text = song.importedNote, !text.isEmpty else { return }
        context.insert(SongNote(songID: song.id, text: text, x: 0.6, y: 0.02, width: 0.34, height: 0.12))
        song.importedNote = nil
    }
}

/// Låtens notes ovanpå låtbladet. Notes som följer sidan placeras utifrån bladets
/// scrollposition och bredd; notes som sitter fast på skärmen ligger still.
struct NotesLayer: View {
    let song: Song
    let geometry: SheetGeometry
    @Environment(Player.self) private var player
    @Query private var notes: [SongNote]

    init(song: Song, geometry: SheetGeometry) {
        self.song = song
        self.geometry = geometry
        let id = song.id
        _notes = Query(filter: #Predicate<SongNote> { $0.songID == id }, sort: \SongNote.created)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.allowsHitTesting(false)
            if !player.notesHidden {
                ForEach(notes) { note in
                    NoteCard(
                        note: note,
                        scale: note.pinned ? 1 : geometry.unit,
                        origin: note.pinned ? .zero : geometry.offset,
                        editable: !player.isLocked
                    ) {
                        player.editingNoteID = note.id
                    }
                }
            }
        }
        .clipped()
    }
}

/// En note: dra för att flytta, dra i hörnet för storlek, tryck för att redigera.
/// Texten anpassas efter noten eller har en låst storlek.
private struct NoteCard: View {
    @Bindable var note: SongNote
    /// Punkter per sparad enhet (bladets bredd för notes som följer sidan, annars 1).
    let scale: CGFloat
    /// Bladets scrollposition (noll för notes som sitter fast på skärmen).
    let origin: CGPoint
    let editable: Bool
    let onTap: () -> Void

    @State private var dragStart: CGPoint?
    @State private var sizeStart: CGSize?

    private var width: CGFloat { CGFloat(note.width) * scale }
    private var height: CGFloat { CGFloat(note.height) * scale }

    var body: some View {
        Text(note.text)
            .font(.system(size: note.fixedFontSize.map { CGFloat($0) * scale } ?? 80, weight: .semibold))
            .minimumScaleFactor(note.fixedFontSize == nil ? 0.05 : 1)
            .multilineTextAlignment(.center)
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: width, height: height)
            .background(Color(uiColor: UIColor(hex: note.colorHex)), in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .topLeading) {
                if note.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.black.opacity(0.5))
                        .padding(5)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if editable {
                    Image(systemName: "arrow.down.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black.opacity(0.45))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                            DragGesture(coordinateSpace: .global)
                                .onChanged { value in
                                    let start = sizeStart ?? CGSize(width: note.width, height: note.height)
                                    sizeStart = start
                                    note.width = max(70 / scale, start.width + value.translation.width / scale)
                                    note.height = max(44 / scale, start.height + value.translation.height / scale)
                                }
                                .onEnded { _ in sizeStart = nil }
                        )
                        .accessibilityLabel("Ändra storlek")
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        guard editable else { return }
                        let start = dragStart ?? CGPoint(x: note.x, y: note.y)
                        dragStart = start
                        note.x = start.x + value.translation.width / scale
                        note.y = max(0, start.y + value.translation.height / scale)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture {
                if editable { onTap() }
            }
            // Positionen sist, så att bara noten (inte hela skärmen) tar emot fingret.
            .position(
                x: CGFloat(note.x) * scale - origin.x + width / 2,
                y: CGFloat(note.y) * scale - origin.y + height / 2
            )
            .accessibilityLabel("Note: \(note.text)")
            .accessibilityHint("Tryck för att redigera")
    }
}

/// Hopplinjerna: rosa streckade linjer med nummer. I redigeringsläget kan man dra i
/// numret för att flytta linjen och trycka på det för att byta nummer eller ta bort.
struct MarkersLayer: View {
    let song: Song
    let geometry: SheetGeometry
    @Environment(Player.self) private var player
    @Environment(\.modelContext) private var context
    @Query private var markers: [JumpMarker]
    @State private var dragStart: Double?
    @State private var choosing: JumpMarker?

    init(song: Song, geometry: SheetGeometry) {
        self.song = song
        self.geometry = geometry
        let id = song.id
        _markers = Query(filter: #Predicate<JumpMarker> { $0.songID == id }, sort: \JumpMarker.number)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear.allowsHitTesting(false)
                if player.editingMarkers || player.showsMarkers {
                    ForEach(markers) { marker in
                        let y = CGFloat(marker.y) * geometry.unit - geometry.offset.y
                        HStack(spacing: 0) {
                            Text("\(marker.number)")
                                .font(.system(size: 16, weight: .bold))
                                .monospacedDigit()
                                .frame(width: 36, height: 36)
                                .background(Color.accentColor, in: Circle())
                                .foregroundStyle(.black)
                                .gesture(drag(marker))
                                .onTapGesture {
                                    if player.editingMarkers { choosing = marker }
                                }
                                .accessibilityLabel("Hopplinje \(marker.number)")
                            Line()
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [8, 6]))
                                .frame(height: 2.5)
                                .allowsHitTesting(false)
                        }
                        .frame(width: proxy.size.width)
                        .position(x: proxy.size.width / 2, y: y)
                        .opacity(player.editingMarkers ? 1 : 0.55)
                    }
                }
            }
        }
        .clipped()
        .confirmationDialog("Hopplinje \(choosing?.number ?? 0)", isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } }), titleVisibility: .visible) {
            ForEach(1...10, id: \.self) { number in
                if number != choosing?.number {
                    Button("Byt till nummer \(number)") {
                        choosing?.number = number
                        choosing = nil
                    }
                }
            }
            Button("Ta bort linjen", role: .destructive) {
                if let marker = choosing { context.delete(marker) }
                choosing = nil
            }
        }
    }

    private func drag(_ marker: JumpMarker) -> some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                guard player.editingMarkers else { return }
                let start = dragStart ?? marker.y
                dragStart = start
                marker.y = max(0, start + Double(value.translation.height / geometry.unit))
            }
            .onEnded { _ in dragStart = nil }
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// Redigera en note: text, textstorlek, färg, förankring och "Ta bort".
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
                Section("Textstorlek") {
                    Toggle("Anpassa texten efter noten", isOn: Binding(
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
                Section("Förankring") {
                    Picker("Förankring", selection: Binding(get: { note.pinned }, set: setPinned)) {
                        Text("Följer sidan").tag(false)
                        Text("Fast på skärmen").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button("Ta bort noten", role: .destructive) {
                        context.delete(note)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    UndoButtons()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") { dismiss() }
                }
            }
            .onAppear { focused = note.text.isEmpty || note.text == "Ny note" }
        }
    }

    /// Textstorlek i punkter ↔ det som sparas (andel av bladets bredd för notes som följer sidan).
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

/// Raden för att rita: markeringspenna eller penna, färgerna, suddet (tre storlekar),
/// ångra och "Stäng av".
struct PenBar: View {
    @Environment(Player.self) private var player
    @AppStorage("inkColor") private var inkColor = NoteColors.inks[0]
    @AppStorage("highlightColor") private var highlightColor = NoteColors.pens[0]
    /// Senaste verktyget (markering eller penna) – suddet byter tillbaka dit.
    @State private var lastTool: Tool = .highlighter

    private enum Tool {
        case highlighter, ink
    }

    private var tool: Tool {
        switch player.pen {
        case .ink: return .ink
        case .color: return .highlighter
        default: return lastTool
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                toolButton(.highlighter, systemImage: "highlighter", label: "Markeringspenna")
                toolButton(.ink, systemImage: "pencil.tip", label: "Penna")
            }
            .padding(2)
            .background(Color(.tertiarySystemFill), in: Capsule())

            let colors = tool == .ink ? NoteColors.inks : NoteColors.pens
            ForEach(colors, id: \.self) { hex in
                let selected = player.pen == .color(hex) || player.pen == .ink(hex)
                Button {
                    choose(hex)
                } label: {
                    Group {
                        if tool == .ink {
                            Circle()
                                .fill(Color(uiColor: UIColor(hex: hex)))
                                .frame(width: 24, height: 24)
                        } else {
                            Capsule()
                                .fill(Color(uiColor: UIColor(hex: hex)))
                                .frame(width: 34, height: 22)
                        }
                    }
                    .padding(3)
                    .overlay(Capsule().stroke(selected ? Color.primary : .clear, lineWidth: 3))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tool == .ink ? "Pennfärg" : "Markeringsfärg")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }

            Divider().frame(height: 28)

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
            if player.pen == .eraser {
                // Suddets storlek: liten, mellan, stor.
                ForEach(0..<Player.eraserRadii.count, id: \.self) { index in
                    let selected = player.eraserSize == index
                    Button {
                        player.eraserSize = index
                    } label: {
                        Circle()
                            .stroke(Color.primary, lineWidth: 1.5)
                            .background(Circle().fill(selected ? Color.accentColor.opacity(0.5) : .clear))
                            .frame(width: CGFloat(10 + index * 7), height: CGFloat(10 + index * 7))
                            .frame(width: 32, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(["Litet sudd", "Mellanstort sudd", "Stort sudd"][index])
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            UndoButtons()
            Button {
                player.pen = .off
            } label: {
                Text("Stäng av")
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
        .onAppear {
            if case .ink = player.pen { lastTool = .ink }
        }
    }

    private func toolButton(_ value: Tool, systemImage: String, label: String) -> some View {
        let selected = tool == value && player.pen != .eraser
        return Button {
            lastTool = value
            switch value {
            case .highlighter: player.pen = .color(highlightColor)
            case .ink: player.pen = .ink(inkColor)
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 36)
                .foregroundStyle(selected ? Color.black : Color.primary)
                .background(selected ? Color.accentColor : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func choose(_ hex: String) {
        switch tool {
        case .ink:
            inkColor = hex
            player.pen = .ink(hex)
        case .highlighter:
            highlightColor = hex
            player.pen = .color(hex)
        }
    }
}

/// Fältet för hopplinjer: lägg till en linje (längst ner på skärmen) och stäng.
struct MarkerBar: View {
    let song: Song
    let geometry: SheetGeometry
    @Environment(Player.self) private var player
    @Environment(\.modelContext) private var context
    @Query private var markers: [JumpMarker]

    init(song: Song, geometry: SheetGeometry) {
        self.song = song
        self.geometry = geometry
        let id = song.id
        _markers = Query(filter: #Predicate<JumpMarker> { $0.songID == id })
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("Hopplinjer \(markers.count)/10")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Button {
                let used = Set(markers.map(\.number))
                guard let number = (1...10).first(where: { !used.contains($0) }) else { return }
                // Längst ner på skärmen: där stycket man ser just nu slutar.
                let y = max(geometry.visibleTop, geometry.visibleBottom - 0.04)
                context.insert(JumpMarker(songID: song.id, y: y, number: number))
            } label: {
                Label("Linje", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .disabled(markers.count >= 10)
            UndoButtons()
            Button {
                player.editingMarkers = false
            } label: {
                Text("Klar")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
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
