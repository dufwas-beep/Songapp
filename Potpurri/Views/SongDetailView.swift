import SwiftData
import SwiftUI
import UIKit

/// Låten som spelas: låtbladet, autoscrollknappen i hörnet och nästa/förra låt.
/// Pedal, AirTurn och tangentbord: pil ner/höger, Page Down och mellanslag går framåt –
/// till nästa hopplinje om låten har sådana, annars en skärmsida; i slutet kommer nästa
/// låt. Pil upp/vänster och Page Up går bakåt. Ett tryck i låten hoppar till nästa linje.
struct SongDetailView: View {
    let song: Song?
    let previous: Song?
    let next: Song?
    let preview: Song?
    let onSelect: (Song) -> Void
    let onPlayPreview: (Song) -> Void

    @Environment(Player.self) private var player
    @State private var previewHeight: CGFloat = 320
    @State private var showsColors = false
    @State private var autoscroller = Autoscroller()
    @State private var overlay = AnnotationOverlay()
    @State private var geometry = SheetGeometry()
    /// Senaste hopplinjen man hoppat till (index i nummerordning).
    @State private var markerIndex: Int?
    @Environment(\.modelContext) private var context
    @FocusState private var focused: Bool

    var body: some View {
        if let song {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    SongSheetView(song: song) { scrollView in
                        autoscroller.attach(scrollView)
                        overlay.attach(to: scrollView)
                        geometry.attach(scrollView)
                        ClosureTap.attach(to: scrollView, name: "potpurri.jump") { jumpOnTap() }
                    }
                    .id(song.id)
                    .background { AnnotationSync(song: song, overlay: overlay).id(song.id) }
                    MarkersLayer(song: song, geometry: geometry)
                        .id(song.id)
                    NotesLayer(song: song, geometry: geometry)
                        .id(song.id)
                    HStack(alignment: .center, spacing: 12) {
                        if !player.isLocked {
                            moreMenu(for: song)
                        }
                        AutoscrollButton(autoscroller: autoscroller, seconds: secondsBinding(for: song))
                    }
                    .padding(24)
                }
                .overlay(alignment: .topTrailing) {
                    SongStepButtons(previous: previous, next: next, onSelect: onSelect)
                        .padding(16)
                }
                .overlay(alignment: .top) {
                    if player.pen != .off && !player.isLocked {
                        PenBar()
                            .padding(.top, 90)
                    } else if player.editingMarkers && !player.isLocked {
                        MarkerBar(song: song, geometry: geometry)
                            .padding(.top, 90)
                    }
                }
                if let preview {
                    PreviewPane(song: preview, height: $previewHeight) {
                        onPlayPreview(preview)
                    } onClose: {
                        player.previewID = nil
                    }
                }
            }
            .overlay(alignment: .top) {
                if player.isLocked {
                    Label("Scenlås", systemImage: "lock.fill")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.black)
                        .padding(.top, 8)
                        .accessibilityLabel("Scenlåset är på")
                }
            }
            .sheet(isPresented: Binding(get: { player.editingNoteID != nil }, set: { if !$0 { player.editingNoteID = nil } })) {
                if let id = player.editingNoteID {
                    NoteEditorLoader(id: id, unit: geometry.unit)
                }
            }
            .navigationTitle(song.title)
            .navigationBarTitleDisplayMode(.inline)
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onKeyPress(keys: [.downArrow, .rightArrow, .pageDown, .space]) { _ in
                forward()
                return .handled
            }
            .onKeyPress(keys: [.upArrow, .leftArrow, .pageUp]) { _ in
                backward()
                return .handled
            }
            .task(id: song.id) {
                autoscroller.stop()
                markerIndex = nil
                player.editingMarkers = false
                autoscroller.duration = TimeInterval(song.autoscrollSeconds ?? 180)
                focused = true
                if let next, next.kind == .pdf { PDFCache.shared.preload(next.fileURL) }
                // En låt räknas som spelad när den varit öppen i 30 sekunder.
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                song.playCount += 1
                song.lastPlayed = Date()
            }
        } else {
            ContentUnavailableView(
                "Välj en låt",
                systemImage: "music.note",
                description: Text("Välj en låt i listan till vänster.")
            )
        }
    }

    /// Menyn ⋯ nere till höger (som i skissen): notes, hopplinjer, penna och färgkoder.
    private func moreMenu(for song: Song) -> some View {
        Menu {
            Button {
                let note = SongNote(songID: song.id, text: "Ny note", x: 0.55, y: geometry.visibleTop + 0.06, width: 0.3, height: 0.1)
                context.insert(note)
                player.notesHidden = false
                player.editingNoteID = note.id
            } label: {
                Label("Ny note", systemImage: "note.text.badge.plus")
            }
            Button {
                player.notesHidden.toggle()
            } label: {
                Label(player.notesHidden ? "Visa notes" : "Dölj notes", systemImage: player.notesHidden ? "eye" : "eye.slash")
            }
            Button {
                player.showsMarkers = true
                player.editingMarkers = true
                player.pen = .off
            } label: {
                Label("Hopplinjer", systemImage: "arrow.down.to.line")
            }
            Button {
                player.pen = .color(NoteColors.pens[0])
            } label: {
                Label("Markeringspenna", systemImage: "highlighter")
            }
            Divider()
            Button {
                showsColors = true
            } label: {
                Label("Färgkoder", systemImage: "paintpalette")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 60, height: 60)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .accessibilityLabel("Fler funktioner")
        .popover(isPresented: $showsColors) {
            SongColorsPanel(song: song)
        }
    }

    private func secondsBinding(for song: Song) -> Binding<Int> {
        Binding(
            get: { song.autoscrollSeconds ?? 180 },
            set: { newValue in
                song.autoscrollSeconds = newValue
                autoscroller.duration = TimeInterval(newValue)
            }
        )
    }

    /// Låtens hopplinjer i nummerordning.
    private func markers() -> [JumpMarker] {
        guard let id = song?.id else { return [] }
        let descriptor = FetchDescriptor<JumpMarker>(predicate: #Predicate { $0.songID == id }, sortBy: [SortDescriptor(\.number)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Hoppa till nästa/förra hopplinje (den hamnar högst upp). False om det inte finns någon.
    private func jump(forward: Bool) -> Bool {
        let list = markers()
        guard !list.isEmpty else { return false }
        let target: Int
        if forward {
            target = (markerIndex ?? -1) + 1
        } else {
            guard let current = markerIndex else { return false }
            target = current - 1
        }
        guard list.indices.contains(target) else {
            if !forward { markerIndex = nil; geometry.scroll(toTop: 0) ; return true }
            return false
        }
        markerIndex = target
        geometry.scroll(toTop: list[target].y)
        return true
    }

    /// Ett tryck i låten hoppar till nästa hopplinje (när låten har sådana).
    private func jumpOnTap() {
        guard !player.editingMarkers, player.pen == .off else { return }
        _ = jump(forward: true)
    }

    private func forward() {
        if jump(forward: true) { return }
        if !markers().isEmpty, let next {
            // Sista linjen är nådd – nästa tryck på pedalen går till nästa låt.
            onSelect(next)
            return
        }
        if !autoscroller.page(forward: true), let next {
            onSelect(next)
        }
    }

    private func backward() {
        if jump(forward: false) { return }
        if !autoscroller.page(forward: false), let previous {
            onSelect(previous)
        }
    }
}

/// Förra och nästa låt, nere till höger bredvid autoscrollknappen. Nästa visar låtens namn.
private struct SongStepButtons: View {
    let previous: Song?
    let next: Song?
    let onSelect: (Song) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if let previous { onSelect(previous) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 52, height: 56)
            }
            .disabled(previous == nil)
            .accessibilityLabel(previous.map { "Förra låten: \($0.title)" } ?? "Ingen förra låt")

            Divider()
                .frame(height: 30)

            Button {
                if let next { onSelect(next) }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("NÄSTA")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                        Text(next?.title ?? "Slut på listan")
                            .font(.system(size: 16, weight: .medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 240, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 18, weight: .semibold))
                }
                .padding(.leading, 14)
                .padding(.trailing, 16)
                .frame(height: 56)
            }
            .disabled(next == nil)
            .accessibilityLabel(next.map { "Nästa låt: \($0.title)" } ?? "Ingen nästa låt")
        }
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}

/// Låtbladet för en låt: textlåt/anteckning, PDF eller bild.
struct SongSheetView: View {
    let song: Song
    let onScrollView: (UIScrollView) -> Void

    var body: some View {
        if song.kind == .text || song.kind == .note {
            TextSongView(song: song, onScrollView: onScrollView)
        } else if !FileManager.default.fileExists(atPath: song.fileURL.path) {
            ContentUnavailableView(
                "Filen saknas",
                systemImage: "exclamationmark.triangle",
                description: Text("Låtens fil hittades inte. Importera den igen.")
            )
        } else if song.kind == .pdf {
            // Zoomen sparas per låt och återställs när låten öppnas igen.
            PDFKitView(url: song.fileURL, zoom: song.pdfZoom, onZoom: { song.pdfZoom = $0 }, onScrollView: onScrollView)
        } else {
            ImageSongView(url: song.fileURL, onScrollView: onScrollView)
        }
    }
}

/// Förhandsrutan under huvudlåten: ett förslag man tittar på medan låten spelas.
/// Dra i överkanten för att ändra storlek. Tryck på låten i rutan för att byta till den.
private struct PreviewPane: View {
    let song: Song
    @Binding var height: CGFloat
    let onPlay: () -> Void
    let onClose: () -> Void

    @State private var startHeight: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("NÄSTA?")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text(song.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Stäng förhandsrutan")
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(.bar)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 56, height: 5)
                    .padding(.top, 5)
            }
            .gesture(
                // Mät i skärmens koordinater – kanten flyttar sig själv när rutan ändrar
                // storlek, och mätt mot den skulle rutan darra.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = startHeight ?? height
                        startHeight = start
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            height = min(max(start - value.translation.height, 160), 720)
                        }
                    }
                    .onEnded { value in
                        startHeight = nil
                        // Svep nedåt långt = stäng.
                        if value.translation.height > 140 { onClose() }
                    }
            )
            // Ett tryck i låten byter till den (scrollning och zoom fungerar som vanligt).
            SongSheetView(song: song) { scrollView in
                ClosureTap.attach(to: scrollView, name: "potpurri.tapToPlay", action: onPlay)
            }
            .id(song.id)
        }
        .frame(height: height)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.accentColor).frame(height: 2)
        }
    }
}

/// Inne i låten: fem stora knappar för låtens färgkoder.
private struct SongColorsPanel: View {
    let song: Song
    @Environment(ColorCodes.self) private var codes
    @State private var showsNames = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Färgkoder för \(song.title)")
                .font(.headline)
                .lineLimit(1)
            ForEach(0..<ColorCodes.count, id: \.self) { index in
                let isOn = song.colorTags.contains(index)
                Button {
                    song.toggleColor(index)
                } label: {
                    HStack(spacing: 12) {
                        Circle().fill(ColorCodes.colors[index]).frame(width: 18, height: 18)
                        Text(codes.names[index])
                            .font(.body.weight(isOn ? .semibold : .regular))
                        Spacer()
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isOn ? ColorCodes.colors[index] : .secondary)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .background(isOn ? ColorCodes.colors[index].opacity(0.18) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(20)
        .frame(width: 340)
        .safeAreaInset(edge: .bottom) {
            Button {
                showsNames = true
            } label: {
                Label("Byt namn på färgerna", systemImage: "pencil")
            }
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $showsNames) {
            ColorNamesSheet()
        }
    }
}

/// Hämtar lappen som ska redigeras.
private struct NoteEditorLoader: View {
    let unit: CGFloat
    @Query private var notes: [SongNote]

    init(id: UUID, unit: CGFloat) {
        self.unit = unit
        _notes = Query(filter: #Predicate<SongNote> { $0.id == id })
    }

    var body: some View {
        if let note = notes.first {
            NoteEditor(note: note, unit: unit)
        }
    }
}

/// Ett tryck på en scrollvy som kör en åtgärd (byt till förhandslåten, hoppa till nästa
/// hopplinje). Läggs direkt på scrollvyn så att det fungerar även för PDF:er.
final class ClosureTap: UITapGestureRecognizer {
    private let action: () -> Void

    private init(name: String, action: @escaping () -> Void) {
        self.action = action
        super.init(target: nil, action: nil)
        self.name = name
        addTarget(self, action: #selector(fire))
    }

    @objc private func fire() {
        action()
    }

    static func attach(to view: UIView, name: String, action: @escaping () -> Void) {
        view.gestureRecognizers?.filter { $0.name == name }.forEach(view.removeGestureRecognizer)
        view.addGestureRecognizer(ClosureTap(name: name, action: action))
    }
}
