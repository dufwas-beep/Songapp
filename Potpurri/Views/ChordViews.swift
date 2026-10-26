import PDFKit
import SwiftData
import SwiftUI
import UIKit

/// Ackordstämplarna ovanpå låtbladet, plus paletten när den är öppen.
/// Ackorden ritas utifrån bladets scrollposition och bredd, så de följer låten.
struct ChordsLayer: View {
    @Bindable var song: Song
    let geometry: SheetGeometry

    @Environment(Player.self) private var player
    @Environment(\.modelContext) private var context
    @Query private var chords: [ChordStamp]

    @State private var paletteOffset: CGSize = .zero
    @State private var paletteDragStart: CGSize?
    @State private var paletteFrame: CGRect = .zero
    /// Ackordet som dras ut från paletten och var fingret är.
    @State private var dragged: (root: Int, quality: String)?
    @State private var dragLocation: CGPoint = .zero
    @State private var menuChord: ChordStamp?
    /// Rutan man drar med fingret i "Välj ackord".
    @State private var lasso: CGRect?

    static let space = "chords"

    init(song: Song, geometry: SheetGeometry) {
        self.song = song
        self.geometry = geometry
        let id = song.id
        _chords = Query(filter: #Predicate<ChordStamp> { $0.songID == id })
    }

    private var key: ChordTheory.Key {
        ChordTheory.key(from: song.key)
    }

    private var editable: Bool {
        player.chordsOn && !player.isLocked
    }

    /// Textstorleken följer bladets bredd, så ackorden zoomar med låten. Storleken kan
    /// ställas in per låt (eller anpassas efter låttexten) i paletten.
    private var fontSize: CGFloat {
        max(10, geometry.unit * CGFloat(song.chordSize ?? 0.026))
    }

    private func labelText(_ chord: ChordStamp) -> String {
        ChordTheory.label(root: chord.root, quality: chord.quality, bass: chord.bass, flats: chord.flats ?? key.usesFlats)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Klistra in: ett tryck på låten lägger sekvensen där.
            if player.pastingChords && editable {
                Color.white.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .named(Self.space)) { location in
                        paste(at: location)
                    }
            } else if player.choosingChords && editable {
                // Dra en ruta med fingret runt ackorden som ska väljas.
                Color.white.opacity(0.001)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
                            .onChanged { value in
                                lasso = CGRect(
                                    x: min(value.startLocation.x, value.location.x),
                                    y: min(value.startLocation.y, value.location.y),
                                    width: abs(value.location.x - value.startLocation.x),
                                    height: abs(value.location.y - value.startLocation.y)
                                )
                            }
                            .onEnded { _ in
                                if let lasso {
                                    for chord in chords where lasso.insetBy(dx: -10, dy: -10).contains(screenPoint(chord)) {
                                        player.selectedChords.insert(chord.id)
                                    }
                                }
                                lasso = nil
                            }
                    )
                if let lasso {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.12))
                        .overlay(Rectangle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                        .frame(width: lasso.width, height: lasso.height)
                        .offset(x: lasso.minX, y: lasso.minY)
                        .allowsHitTesting(false)
                }
            } else {
                Color.clear.allowsHitTesting(false)
            }
            if editable { groupFrames }
            ForEach(chords) { chord in
                stamp(chord)
            }
            if let dragged {
                chordPill(ChordTheory.label(root: dragged.root, quality: dragged.quality, bass: nil, in: key), selected: true)
                    .position(dragLocation)
                    .allowsHitTesting(false)
            }
            if player.chordsOn && !player.isLocked {
                palette
                    .offset(paletteOffset)
                    .padding(16)
                    .padding(.top, 70)
            }
        }
        .coordinateSpace(name: Self.space)
        .clipped()
    }

    // MARK: Ackorden på låten

    private func screenPoint(_ chord: ChordStamp) -> CGPoint {
        CGPoint(x: CGFloat(chord.x) * geometry.unit - geometry.offset.x, y: CGFloat(chord.y) * geometry.unit - geometry.offset.y)
    }

    private func stamp(_ chord: ChordStamp) -> some View {
        let label = labelText(chord)
        let point = screenPoint(chord)
        let selected = player.selectedChords.contains(chord.id)
        // Ackordet (och hela gruppen) som dras lyfts: rosa, lite större och med skugga.
        let lifted = draggingGroup.contains(chord.id)
        return chordPill(label, selected: selected || lifted)
            .scaleEffect(lifted ? 1.18 : 1)
            .shadow(color: .black.opacity(lifted ? 0.35 : 0), radius: 8, y: 4)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: lifted)
            // Minst 44 punkter hög tryckyta, så att ackordet är lätt att träffa.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .fixedSize()
            .gesture(moveGesture(chord), including: editable && !player.choosingChords ? .all : .none)
            // Tryck (eller håll in) öppnar menyn; i "Välj ackord" markerar ett tryck i stället.
            .onTapGesture {
                guard editable else { return }
                if player.choosingChords {
                    if selected { player.selectedChords.remove(chord.id) } else { player.selectedChords.insert(chord.id) }
                } else {
                    menuChord = chord
                }
            }
            .popover(isPresented: Binding(get: { menuChord?.id == chord.id }, set: { if !$0 { menuChord = nil } })) {
                ChordMenu(chord: chord, key: key) { action in
                    handle(action, for: chord)
                }
            }
            // Ackorden går bara att ta i när paletten är öppen – annars scrollar man som vanligt.
            .allowsHitTesting(editable)
            .position(x: point.x + estimatedWidth(label) / 2, y: point.y)
            .accessibilityLabel("Ackord \(label)")
            .accessibilityHint(editable ? "Tryck för att ändra, dra för att flytta" : "")
    }

    private func chordPill(_ label: String, selected: Bool) -> some View {
        Text(label)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(selected ? Color.accentColor : Color(white: 0.93), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.08)))
    }

    private func estimatedWidth(_ label: String) -> CGFloat {
        CGFloat(label.count) * fontSize * 0.62 + 14
    }

    /// Kort drag flyttar ackordet – eller hela gruppen om det sitter i en.
    private func moveGesture(_ chord: ChordStamp) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
            .onChanged { value in
                let members = group(of: chord)
                if draggingGroup.isEmpty { draggingGroup = Set(members.map(\.id)) }
                let dx = Double(value.translation.width - lastTranslation.width) / Double(geometry.unit)
                let dy = Double(value.translation.height - lastTranslation.height) / Double(geometry.unit)
                lastTranslation = value.translation
                for member in members {
                    member.x += dx
                    member.y += dy
                }
            }
            .onEnded { _ in
                lastTranslation = .zero
                draggingGroup = []
                withAnimation(.easeOut(duration: 0.15)) {
                    snapToRow(group(of: chord))
                    resolveOverlaps(row(of: chord))
                }
            }
    }

    @State private var lastTranslation: CGSize = .zero
    /// Ackorden som dras just nu (ett ackord eller hela dess grupp).
    @State private var draggingGroup: Set<UUID> = []

    /// Ackorden på samma rad som ett ackord.
    private func row(of chord: ChordStamp) -> [ChordStamp] {
        chords.filter { abs($0.y - chord.y) < 0.004 }
    }

    /// Avståndet som behövs mellan två ackord på raden (bredd + luft), i bladets enheter.
    private func minimumGap(after chord: ChordStamp) -> Double {
        Double((estimatedWidth(labelText(chord)) + fontSize * 0.5) / geometry.unit)
    }

    /// Ackord som hamnat på varandra knuffas åt höger så att de aldrig överlappar.
    private func resolveOverlaps(_ row: [ChordStamp]) {
        let sorted = row.sorted { $0.x < $1.x }
        guard sorted.count > 1 else { return }
        for index in 1..<sorted.count {
            let needed = sorted[index - 1].x + minimumGap(after: sorted[index - 1])
            if sorted[index].x < needed { sorted[index].x = needed }
        }
    }

    /// Jämna avstånd: första och sista ackordet ligger kvar, de andra fördelas jämnt
    /// emellan (men aldrig tätare än att de får plats).
    private func spaceEvenly(_ members: [ChordStamp]) {
        let sorted = members.sorted { $0.x < $1.x }
        guard sorted.count > 2, let first = sorted.first, let last = sorted.last else {
            resolveOverlaps(members)
            return
        }
        let widest = sorted.map(minimumGap(after:)).max() ?? 0
        let step = max((last.x - first.x) / Double(sorted.count - 1), widest)
        withAnimation(.easeOut(duration: 0.2)) {
            for (index, chord) in sorted.enumerated() {
                chord.x = first.x + step * Double(index)
                chord.y = first.y
            }
        }
    }

    private func group(of chord: ChordStamp) -> [ChordStamp] {
        guard let groupID = chord.groupID else { return [chord] }
        return chords.filter { $0.groupID == groupID }
    }

    /// Hamnar ackordet nära höjden för andra ackord snäpper det till samma rad.
    private func snapToRow(_ members: [ChordStamp]) {
        guard let first = members.first else { return }
        let ids = Set(members.map(\.id))
        let others = chords.filter { !ids.contains($0.id) }
        guard let nearest = others.min(by: { abs($0.y - first.y) < abs($1.y - first.y) }),
              abs(nearest.y - first.y) < 0.018 else { return }
        let shift = nearest.y - first.y
        for member in members { member.y += shift }
    }

    // MARK: Grupper

    /// Varje grupp visas som en streckad ram med en rosa flik "Grupp". Dra i fliken eller
    /// var som helst i ramen för att flytta hela gruppen.
    private var groupFrames: some View {
        let groups = Dictionary(grouping: chords.filter { $0.groupID != nil }, by: { $0.groupID! })
        return ForEach(Array(groups.keys), id: \.self) { id in
            let members = groups[id] ?? []
            if members.count > 1 {
                let points = members.map(screenPoint)
                let minX = (points.map(\.x).min() ?? 0) - 8
                let maxX = zip(points, members).map { $0.0.x + estimatedWidth(labelText($0.1)) }.max() ?? 0
                let minY = (points.map(\.y).min() ?? 0) - 26
                let maxY = (points.map(\.y).max() ?? 0) + 26
                let rect = CGRect(x: minX, y: minY, width: maxX - minX + 8, height: maxY - minY)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
                    // Tryck på fliken: dela upp, kopiera eller ta bort hela gruppen.
                    Menu {
                        Button {
                            members.forEach { $0.groupID = nil }
                        } label: {
                            Label("Dela upp gruppen", systemImage: "rectangle.split.3x1")
                        }
                        Button {
                            copy(members)
                        } label: {
                            Label("Kopiera gruppen", systemImage: "doc.on.doc")
                        }
                        Button {
                            spaceEvenly(members)
                        } label: {
                            Label("Jämna ut avstånden", systemImage: "arrow.left.and.right")
                        }
                        Button(role: .destructive) {
                            members.forEach { context.delete($0) }
                        } label: {
                            Label("Ta bort gruppen", systemImage: "trash")
                        }
                    } label: {
                        Label("Grupp", systemImage: "chevron.down")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    .offset(x: 6, y: -26)
                }
                .frame(width: rect.width, height: rect.height)
                .contentShape(Rectangle())
                .position(x: rect.midX, y: rect.midY)
                .gesture(moveGesture(members[0]), including: player.choosingChords ? .none : .all)
            }
        }
    }

    // MARK: Menyn för ett ackord

    enum MenuAction {
        case evenRow
        case accidental(Int)
        case quality(String)
        case bass(Int?)
        case copy
        case delete
    }

    private func handle(_ action: MenuAction, for chord: ChordStamp) {
        switch action {
        case .evenRow:
            spaceEvenly(row(of: chord))
            menuChord = nil
        case .accidental(let step):
            // ♯ höjer (stavas med #), ♭ sänker (stavas med b), ♮ tar bort förtecknet.
            // Bara det här ackordet ändras – inte låtens tonart.
            if step == 0 {
                let name = labelText(chord)
                chord.root = ChordTheory.pitch(of: String(name.prefix(1))) ?? chord.root
            } else {
                chord.root = (chord.root + step + 12) % 12
                chord.flats = step < 0
            }
        case .quality(let quality):
            chord.quality = quality
        case .bass(let bass):
            chord.bass = bass
        case .copy:
            copy(group(of: chord))
            menuChord = nil
        case .delete:
            context.delete(chord)
            menuChord = nil
        }
    }

    private func copy(_ members: [ChordStamp]) {
        let sorted = members.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        guard let first = sorted.first else { return }
        player.chordClipboard = sorted.map { .init(root: $0.root, quality: $0.quality, bass: $0.bass, flats: $0.flats ?? key.usesFlats, dx: $0.x - first.x, dy: $0.y - first.y) }
        player.pastingChords = true
        player.choosingChords = false
        player.selectedChords = []
    }

    /// Klistra in: avstånden mellan ackorden behålls och sekvensen blir en grupp.
    private func paste(at location: CGPoint) {
        let x = Double((location.x + geometry.offset.x) / geometry.unit)
        let y = Double((location.y + geometry.offset.y) / geometry.unit)
        let groupID = player.chordClipboard.count > 1 ? UUID() : nil
        for item in player.chordClipboard {
            let chord = ChordStamp(songID: song.id, root: item.root, quality: item.quality, bass: item.bass, x: x + item.dx, y: y + item.dy, groupID: groupID)
            chord.flats = item.flats
            context.insert(chord)
        }
        player.pastingChords = false
    }

    // MARK: Paletten

    private var palette: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 32)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                let start = paletteDragStart ?? paletteOffset
                                paletteDragStart = start
                                paletteOffset = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
                            }
                            .onEnded { _ in paletteDragStart = nil }
                    )
                    .accessibilityLabel("Flytta paletten")
                Text("Ackord").font(.headline)
                Spacer()
                Button {
                    player.chordsOn = false
                    player.choosingChords = false
                    player.pastingChords = false
                    player.selectedChords = []
                } label: {
                    Image(systemName: "xmark").frame(width: 32, height: 32)
                }
                .accessibilityLabel("Stäng ackordpaletten")
            }
            HStack(spacing: 8) {
                Menu {
                    ForEach(ChordTheory.allKeys, id: \.self) { option in
                        Button(option.name + (option.minor ? " (moll)" : " (dur)")) { song.key = option.name }
                    }
                } label: {
                    Text("Tonart: \(key.name)")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                Spacer()
                // ♭/♯ byter bara palettens tonart (t.ex. för refrängen) – ackord som redan
                // ligger på låten ändras inte.
                Button { stepPaletteKey(-1) } label: { Text("♭").font(.title3.weight(.bold)).frame(width: 30) }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Palettens tonart ett halvt tonsteg ner")
                Button { stepPaletteKey(1) } label: { Text("♯").font(.title3.weight(.bold)).frame(width: 30) }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Palettens tonart ett halvt tonsteg upp")
            }
            HStack(spacing: 8) {
                Image(systemName: "textformat.size")
                    .foregroundStyle(.secondary)
                Slider(value: Binding(get: { song.chordSize ?? 0.026 }, set: { song.chordSize = $0 }), in: 0.014...0.06)
                    .accessibilityLabel("Ackordens storlek")
                Button("Som texten") { song.chordSize = textSize() }
                    .font(.footnote)
                    .buttonStyle(.bordered)
            }
            Menu {
                Button("Upp ett halvt tonsteg") { transpose(1) }
                Button("Ner ett halvt tonsteg") { transpose(-1) }
            } label: {
                Label("Transponera hela låten", systemImage: "arrow.up.arrow.down")
                    .font(.footnote.weight(.semibold))
            }
            Text("Dra ut ett ackord till låten")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(Array(ChordTheory.diatonicChords(in: key).enumerated()), id: \.offset) { _, chord in
                    paletteChip(root: chord.root, quality: chord.quality)
                }
            }
            Divider()
            if player.pastingChords {
                HStack {
                    Text("Tryck där sekvensen ska klistras in")
                        .font(.footnote)
                    Spacer()
                    Button("Avbryt") { player.pastingChords = false }
                }
            } else if player.choosingChords {
                chooseBar
            } else {
                Button {
                    player.choosingChords = true
                    player.selectedChords = []
                } label: {
                    Label("Välj ackord", systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        .background {
            GeometryReader { proxy in
                Color.clear.onAppear { paletteFrame = proxy.frame(in: .named(Self.space)) }
                    .onChange(of: proxy.frame(in: .named(Self.space))) { _, frame in paletteFrame = frame }
            }
        }
    }

    private var chooseBar: some View {
        let selected = chords.filter { player.selectedChords.contains($0.id) }
        return VStack(alignment: .leading, spacing: 8) {
            Text(selected.isEmpty ? "Tryck på ackorden – eller dra en ruta runt dem" : "\(selected.count) valda")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button("Gruppera") {
                    let id = UUID()
                    selected.forEach { $0.groupID = id }
                    finishChoosing()
                }
                .disabled(selected.count < 2)
                Button("Dela upp") {
                    selected.forEach { $0.groupID = nil }
                    finishChoosing()
                }
                .disabled(selected.allSatisfy { $0.groupID == nil })
                Button("Kopiera") { copy(selected) }
                    .disabled(selected.isEmpty)
                Button("Jämna ut") { spaceEvenly(selected) }
                    .disabled(selected.count < 2)
                Button("Ta bort", role: .destructive) {
                    selected.forEach { context.delete($0) }
                    finishChoosing()
                }
                .disabled(selected.isEmpty)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button("Klar") { finishChoosing() }
                .font(.footnote.weight(.semibold))
        }
    }

    private func finishChoosing() {
        player.choosingChords = false
        player.selectedChords = []
    }

    private func paletteChip(root: Int, quality: String) -> some View {
        Text(ChordTheory.label(root: root, quality: quality, bass: nil, in: key))
            .font(.system(size: 16, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Color(white: 0.93), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.black)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        dragged = (root, quality)
                        dragLocation = value.location
                    }
                    .onEnded { value in
                        dragged = nil
                        // Släppt på låten (inte på paletten) → nytt ackord där.
                        guard !paletteFrame.contains(value.location) else { return }
                        let label = ChordTheory.label(root: root, quality: quality, bass: nil, in: key)
                        let left = value.location.x - estimatedWidth(label) / 2
                        let chord = ChordStamp(
                            songID: song.id, root: root, quality: quality,
                            x: Double((left + geometry.offset.x) / geometry.unit),
                            y: Double((value.location.y + geometry.offset.y) / geometry.unit)
                        )
                        // Stavningen följer palettens tonart just nu och står sedan kvar.
                        chord.flats = key.usesFlats
                        context.insert(chord)
                        snapToRow([chord])
                        resolveOverlaps(chords.filter { abs($0.y - chord.y) < 0.004 } + [chord])
                    }
            )
            .accessibilityLabel("Ackord \(ChordTheory.label(root: root, quality: quality, bass: nil, in: key))")
    }

    /// Palettens tonart ett halvt tonsteg upp/ner (ackorden på låten ändras inte).
    private func stepPaletteKey(_ step: Int) {
        song.key = ChordTheory.Key(root: (key.root + step + 12) % 12, minor: key.minor).name
    }

    /// Transponera alla ackord på låten (och tonarten) ett halvt tonsteg. Ackorden stavas
    /// om efter den nya tonarten.
    private func transpose(_ step: Int) {
        let newKey = ChordTheory.Key(root: (key.root + step + 12) % 12, minor: key.minor)
        for chord in chords {
            chord.root = (chord.root + step + 12) % 12
            if let bass = chord.bass { chord.bass = (bass + step + 12) % 12 }
            chord.flats = newKey.usesFlats
        }
        song.key = newKey.name
    }

    /// Ackordstorlek som passar låttexten: textlåtarnas egen storlek, eller den vanligaste
    /// teckenstorleken i PDF:en (i förhållande till sidans bredd).
    private func textSize() -> Double {
        switch song.kind {
        case .text, .note:
            let unit = Double(max(geometry.unit, 1))
            let scale = min(max(unit / 820, 0.8), 1.3) * (song.pdfZoom ?? 1)
            return 22 * scale / unit
        case .pdf:
            guard let page = PDFCache.shared.document(for: song.fileURL)?.page(at: 0),
                  let text = page.attributedString else { return 0.026 }
            var sizes: [CGFloat] = []
            text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
                if let font = value as? UIFont, range.length > 2 {
                    sizes.append(contentsOf: Array(repeating: font.pointSize, count: min(range.length, 200)))
                }
            }
            let width = page.bounds(for: .mediaBox).width
            guard !sizes.isEmpty, width > 0 else { return 0.026 }
            let median = sizes.sorted()[sizes.count / 2]
            return Double(median / width)
        case .image:
            return 0.026
        }
    }
}

/// Menyn när man håller inne ett ackord: förtecken, färgning, bas, kopiera och ta bort.
private struct ChordMenu: View {
    let chord: ChordStamp
    let key: ChordTheory.Key
    let onAction: (ChordsLayer.MenuAction) -> Void
    @State private var showsMore = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(ChordTheory.label(root: chord.root, quality: chord.quality, bass: chord.bass, flats: chord.flats ?? key.usesFlats))
                    .font(.title2.weight(.bold))
                section("Förtecken") {
                    HStack(spacing: 8) {
                        option("♯ Höj") { onAction(.accidental(1)) }
                        option("♮ Ingen") { onAction(.accidental(0)) }
                        option("♭ Sänk") { onAction(.accidental(-1)) }
                    }
                }
                section("Färgning") {
                    let qualities = ChordTheory.commonQualities + (showsMore ? ChordTheory.moreQualities : [])
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                        ForEach(qualities, id: \.self) { quality in
                            option(quality.isEmpty ? "dur" : quality, selected: chord.quality == quality) { onAction(.quality(quality)) }
                        }
                    }
                    Button(showsMore ? "Färre" : "Fler") { showsMore.toggle() }
                        .font(.footnote)
                }
                section("Bas") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                        option("ingen", selected: chord.bass == nil) { onAction(.bass(nil)) }
                        ForEach(0..<12, id: \.self) { pitch in
                            option(ChordTheory.name(pitch, flats: chord.flats ?? key.usesFlats), selected: chord.bass == pitch) { onAction(.bass(pitch)) }
                        }
                    }
                }
                Divider()
                Button {
                    onAction(.evenRow)
                } label: {
                    Label("Jämna ut avstånden på raden", systemImage: "arrow.left.and.right")
                }
                HStack {
                    Button {
                        onAction(.copy)
                    } label: {
                        Label(chord.groupID == nil ? "Kopiera" : "Kopiera gruppen", systemImage: "doc.on.doc")
                    }
                    Spacer()
                    Button(role: .destructive) {
                        onAction(.delete)
                    } label: {
                        Label("Ta bort", systemImage: "trash")
                    }
                }
            }
            .padding(18)
        }
        .frame(width: 340, height: 520)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func option(_ title: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(selected ? Color.accentColor : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(selected ? Color.black : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
