import PDFKit
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
    /// Sidospalten (listorna) är dold – då visas klockan i raden överst.
    var sidebarHidden = false
    var onToggleSidebar: () -> Void = {}

    @Environment(Player.self) private var player
    @Environment(SoundEngine.self) private var sounds
    @State private var previewHeight: CGFloat = 320
    @State private var showsColors = false
    @State private var autoscroller = Autoscroller()
    @State private var overlay = AnnotationOverlay()
    @State private var geometry = SheetGeometry()
    /// Senaste hopplinjen man hoppat till (index i nummerordning).
    @State private var markerIndex: Int?
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focused: Bool
    /// Låten som visas (för att spara var man hade den när man byter).
    @State private var shownSong: Song?
    @State private var restoredSongID: UUID?

    var body: some View {
        if let song {
            VStack(spacing: 0) {
            SongTopBar(
                title: song.title,
                previous: previous,
                next: next,
                sidebarHidden: sidebarHidden,
                onToggleSidebar: onToggleSidebar,
                onSelect: onSelect
            )
            HStack(spacing: 0) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    SongSheetView(song: song) { scrollView in
                        autoscroller.attach(scrollView)
                        overlay.attach(to: scrollView)
                        geometry.attach(scrollView)
                        ClosureTap.attach(to: scrollView, name: "potpurri.jump") { jumpOnTap() }
                        restorePosition(of: song, in: scrollView)
                    }
                    .id(song.id)
                    .background { AnnotationSync(song: song, overlay: overlay).id(song.id) }
                    MarkersLayer(song: song, geometry: geometry)
                        .id(song.id)
                    ChordsLayer(song: song, geometry: geometry)
                        .id(song.id)
                    NotesLayer(song: song, geometry: geometry)
                        .id(song.id)
                    HStack(alignment: .center, spacing: 12) {
                        SpotifyButton()
                        soundboardButton
                        if !player.isLocked {
                            moreMenu(for: song)
                        }
                        // Autoscroll visas bara när låten har en längd (läggs till under ⋯).
                        if song.autoscrollSeconds != nil {
                            AutoscrollButton(autoscroller: autoscroller, seconds: secondsBinding(for: song))
                        }
                    }
                    .padding(24)
                }
                // Lådan i högerkanten (till vänster om soundboarden när den är öppen).
                .overlay(alignment: .trailing) {
                    GeometryReader { proxy in
                        DrawerView(width: min(520, proxy.size.width * 0.48))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    }
                }
                .clipped()
                // Ett quiz (t.ex. HLS 45) har sina låtar i en ruta uppe till vänster.
                .overlay(alignment: .topLeading) {
                    if LibraryView.isQuiz(song) && player.pen == .off && !player.editingMarkers {
                        QuizPanel(quiz: song)
                            .padding(12)
                    }
                }
                .overlay(alignment: .top) {
                    if player.pen != .off && !player.isLocked {
                        PenBar()
                            .padding(.top, 12)
                    } else if player.editingMarkers && !player.isLocked {
                        MarkerBar(song: song, geometry: geometry)
                            .padding(.top, 12)
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
            if player.soundboardOpen {
                SoundboardColumn(engine: sounds)
                    .transition(.move(edge: .trailing))
            }
            }
            }
            .toolbar(.hidden, for: .navigationBar)
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
            .onChange(of: autoscroller.isRunning) { _, running in
                player.isAutoscrolling = running
            }
            // Var man hade låten sparas när man byter låt, lämnar appen eller stänger vyn.
            .onChange(of: song.id) {
                if let shownSong { rememberPosition(of: shownSong) }
                shownSong = song
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { rememberPosition(of: song) }
            }
            .onAppear { shownSong = song }
            .onDisappear { rememberPosition(of: song) }
            .task(id: song.id) {
                autoscroller.stop()
                markerIndex = nil
                player.editingMarkers = false
                player.choosingChords = false
                player.selectedChords = []
                player.pastingChords = false
                autoscroller.duration = TimeInterval(song.autoscrollSeconds ?? 180)
                focused = true
                // Nästa och förra låten läses in i förväg så att bytet går direkt.
                for neighbor in [next, previous].compactMap({ $0 }) {
                    if neighbor.kind == .pdf { PDFPageRenderer.shared.preload(neighbor.fileURL) }
                    if neighbor.kind == .image { ImageCache.shared.preload(neighbor.fileURL) }
                }
                // En låt räknas som spelad när den varit öppen i 30 sekunder.
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                song.playCount += 1
                song.lastPlayed = Date()
                GigLogger.played(song, in: context, since: player.gigStart)
            }
        } else {
            // Ingen låt vald än: välkomstbild med loggan, men Spotify och ljudklippen
            // finns redan – det kan behövas innan första låten.
            VStack(spacing: 0) {
            SongTopBar(
                title: nil,
                previous: nil,
                next: nil,
                sidebarHidden: sidebarHidden,
                onToggleSidebar: onToggleSidebar,
                onSelect: nil
            )
            HStack(spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    VStack(spacing: 18) {
                        ScratchRecord()
                        Text("Hej!")
                            .font(.system(size: 44, weight: .semibold))
                        Text("Välj en låt så kör vi!")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    HStack(spacing: 12) {
                        SpotifyButton()
                        soundboardButton
                    }
                    .padding(24)
                }
                if player.soundboardOpen {
                    SoundboardColumn(engine: sounds)
                        .transition(.move(edge: .trailing))
                }
            }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Högtalarknappen som öppnar och stänger soundboarden.
    private var soundboardButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { player.soundboardOpen.toggle() }
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 60, height: 60)
                .background(player.soundboardOpen ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.regularMaterial), in: Circle())
                .foregroundStyle(player.soundboardOpen ? Color.black : Color.primary)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .guideSpot(.soundboard)
        .accessibilityLabel(player.soundboardOpen ? "Stäng ljudklippen" : "Ljudklipp")
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
                player.chordsOn = false
            } label: {
                Label("Markeringspenna", systemImage: "highlighter")
            }
            Button {
                player.chordsOn = true
                player.pen = .off
                player.editingMarkers = false
            } label: {
                Label("Ackord", systemImage: "music.note")
            }
            if song.autoscrollSeconds == nil {
                Button {
                    song.autoscrollSeconds = 180
                    autoscroller.duration = 180
                } label: {
                    Label("Autoscroll", systemImage: "arrow.down.circle")
                }
            } else {
                Button {
                    autoscroller.stop()
                    song.autoscrollSeconds = nil
                } label: {
                    Label("Ta bort autoscroll", systemImage: "arrow.down.circle.dotted")
                }
            }
            Divider()
            Button {
                showsColors = true
            } label: {
                Label("Kategorier", systemImage: "tag")
            }
            Divider()
            Button {
                player.renamingSongID = song.id
            } label: {
                Label("Byt namn", systemImage: "pencil")
            }
            if song.kind == .pdf {
                Button {
                    makeEditable(song)
                } label: {
                    Label("Gör redigerbar (text)", systemImage: "text.cursor")
                }
            }
            if song.kind == .text || song.kind == .note {
                Button {
                    player.editingTextSongID = song.id
                } label: {
                    Label("Redigera texten", systemImage: "square.and.pencil")
                }
            }
            if song.canRestorePDF {
                Button {
                    song.kindRaw = SongKind.pdf.rawValue
                } label: {
                    Label("Återställ PDF", systemImage: "arrow.uturn.backward")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 60, height: 60)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .guideSpot(.songMenu)
        .accessibilityLabel("Fler funktioner")
        .popover(isPresented: $showsColors) {
            SongColorsPanel(song: song)
        }
    }

    /// "Gör redigerbar": texten plockas ur PDF:en och låten blir en textlåt. Originalfilen
    /// sparas, så låten kan återställas till PDF-visning.
    private func makeEditable(_ song: Song) {
        let text = PDFCache.shared.document(for: song.fileURL)?.string ?? song.searchText ?? ""
        song.text = text.isEmpty ? song.title : text
        song.kindRaw = SongKind.text.rawValue
        player.editingTextSongID = song.id
    }

    /// Sparar var låtbladet står (sidled och höjdled), i förhållande till bladets bredd.
    private func rememberPosition(of song: Song) {
        guard let scrollView = geometry.scrollView, scrollView.contentSize.width > 1 else { return }
        let inset = scrollView.adjustedContentInset
        let width = scrollView.contentSize.width
        song.scrollX = Double(max(0, scrollView.contentOffset.x + inset.left) / width)
        song.scrollY = Double(max(0, scrollView.contentOffset.y + inset.top) / width)
        try? context.save()
    }

    /// Öppnar låten där man hade den: i sidled alltid (en inzoomad låt), i höjdled bara
    /// om man var kvar i början av låten (t.ex. förbi en tom marginal) – annars överst.
    private func restorePosition(of song: Song, in scrollView: UIScrollView) {
        guard restoredSongID != song.id else { return }
        restoredSongID = song.id
        guard song.scrollX != nil || song.scrollY != nil else { return }
        Task {
            // Vänta tills bladet har fått sin storlek.
            try? await Task.sleep(for: .milliseconds(80))
            let inset = scrollView.adjustedContentInset
            let width = scrollView.contentSize.width
            guard width > 1 else { return }
            let maxX = max(-inset.left, width + inset.right - scrollView.bounds.width)
            let maxY = max(-inset.top, scrollView.contentSize.height + inset.bottom - scrollView.bounds.height)
            let x = CGFloat(song.scrollX ?? 0) * width - inset.left
            var y = CGFloat(song.scrollY ?? 0) * width - inset.top
            if y > scrollView.bounds.height * 0.6 { y = -inset.top }
            scrollView.setContentOffset(CGPoint(x: min(max(x, -inset.left), maxX), y: min(max(y, -inset.top), maxY)), animated: false)
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
        // Linjen hamnar nära toppen med lite av texten ovanför kvar som sammanhang.
        geometry.scroll(toTop: list[target].y - Double(90 / geometry.unit))
        return true
    }

    /// Ett tryck i låten hoppar till nästa hopplinje (när låten har sådana).
    private func jumpOnTap() {
        guard !player.editingMarkers, !player.chordsOn, player.pen == .off else { return }
        if jump(forward: true) { return }
        // Alla linjer är använda: börja om högst upp, nästa tryck går till linje 1 igen.
        if !markers().isEmpty {
            markerIndex = nil
            geometry.scroll(toTop: 0)
        }
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

/// Raden överst i låtvyn: knappen för listorna, låtens namn, scenlåset, förra/nästa låt
/// och kugghjulet. Låg, så att låten får så mycket plats som möjligt.
private struct SongTopBar: View {
    let title: String?
    let previous: Song?
    let next: Song?
    let sidebarHidden: Bool
    let onToggleSidebar: () -> Void
    /// nil = ingen låt vald (då visas inte förra/nästa).
    let onSelect: ((Song) -> Void)?
    @Environment(Player.self) private var player

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleSidebar) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .guideSpot(.sidebarToggle)
            .accessibilityLabel(sidebarHidden ? "Visa listorna" : "Dölj listorna")
            if sidebarHidden {
                ClockLabel()
            }
            if let title {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .padding(.leading, 4)
            }
            Spacer(minLength: 8)
            if player.isLocked {
                // Scenlåset visas bredvid Nästa så att det aldrig ligger över den.
                Image(systemName: "lock.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor, in: Circle())
                    .foregroundStyle(.black)
                    .accessibilityLabel("Scenlåset är på")
            }
            if let onSelect {
                SongStepButtons(previous: previous, next: next, onSelect: onSelect)
                    .guideSpot(.stepButtons)
            }
            RecordButton()
            SettingsButton(size: 36)
                .guideSpot(.settings)
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
    }
}

/// Förra och nästa låt i raden överst. Nästa visar låtens namn.
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
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 40)
            }
            .disabled(previous == nil)
            .accessibilityLabel(previous.map { "Förra låten: \($0.title)" } ?? "Ingen förra låt")

            Divider()
                .frame(height: 24)

            Button {
                if let next { onSelect(next) }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("NÄSTA")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                        Text(next?.title ?? "Slut på listan")
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 240, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                }
                .padding(.leading, 12)
                .padding(.trailing, 14)
                .frame(height: 40)
            }
            .disabled(next == nil)
            .accessibilityLabel(next.map { "Nästa låt: \($0.title)" } ?? "Ingen nästa låt")
        }
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: Capsule())
    }
}

/// Låtbladet för en låt: textlåt/anteckning, PDF eller bild.
struct SongSheetView: View {
    let song: Song
    let onScrollView: (UIScrollView) -> Void
    @Environment(Player.self) private var player
    @Environment(\.modelContext) private var context

    /// Zoomen sparas direkt, så att den finns kvar även om appen stängs strax efter.
    private func saveZoom(_ zoom: Double) {
        song.pdfZoom = zoom
        try? context.save()
    }

    var body: some View {
        if song.kind == .text || song.kind == .note {
            TextSongView(song: song, onScrollView: onScrollView)
                .onAppear {
                    player.markSwitchViewBuilt()
                    player.finishSwitchTimer(kind: "text")
                }
        } else if !FileManager.default.fileExists(atPath: song.fileURL.path) {
            ContentUnavailableView(
                "Filen saknas",
                systemImage: "exclamationmark.triangle",
                description: Text("Låtens fil hittades inte. Importera den igen.")
            )
        } else if song.kind == .pdf {
            // Zoomen sparas per låt och återställs när låten öppnas igen.
            PDFPagesView(url: song.fileURL, zoom: song.pdfZoom, onZoom: saveZoom, onScrollView: onScrollView)
                .onAppear { player.markSwitchViewBuilt() }
        } else {
            ImageSongView(url: song.fileURL, zoom: song.pdfZoom, onZoom: saveZoom, onScrollView: onScrollView)
                .onAppear { player.markSwitchViewBuilt() }
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

/// Inne i låten: stora knappar för låtens kategorier.
private struct SongColorsPanel: View {
    let song: Song
    @Environment(ColorCodes.self) private var codes
    @State private var showsNames = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Kategorier för \(song.title)")
                .font(.headline)
                .lineLimit(1)
            ForEach(0..<codes.count, id: \.self) { index in
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
                Label("Namn och antal", systemImage: "pencil")
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
