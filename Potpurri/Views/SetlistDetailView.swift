import SwiftData
import SwiftUI

/// En öppen låtlista: låtarna i ordning, indelade i set med setgränser.
/// Håll in en låt eller setgräns så lossnar den och följer fingret; släpp där den ska
/// ligga (en rosa linje visar var). Låtar från biblioteket kan också släppas i listan.
struct SetlistDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(Player.self) private var player
    @Bindable var setlist: Setlist
    @Query private var songs: [Song]
    @Binding var selection: Song?
    let onClose: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @State private var showAddSongs = false
    /// Raden som dras just nu (och vad den bär) och raden den skulle hamna före.
    @State private var dragging: Int?
    @State private var draggingPayload: String?
    @State private var dropTarget: Int?
    @State private var colorMode = false
    @State private var checked: Set<UUID> = []

    /// En rad i listan med uppgift om vilket set den hör till.
    private struct Row: Identifiable {
        let id: Int
        let item: SetlistItem
        let setNumber: Int
        /// Låtens nummer i sitt set (numreringen börjar om i varje set).
        let number: Int
    }

    private var rows: [Row] {
        var result: [Row] = []
        var setNumber = 1
        var number = 0
        for (index, item) in setlist.items.enumerated() {
            switch item {
            case .setBreak:
                // En gräns överst gör inget nytt set – listan börjar ändå med Set 1.
                if index > 0 { setNumber += 1 }
                number = 0
            case .song:
                number += 1
            }
            result.append(Row(id: index, item: item, setNumber: setNumber, number: number))
        }
        return result
    }

    /// Färgkolumnerna – bara färger som någon låt i just den här listan har (alla i färgläget).
    private var columns: [Int] {
        let ids = Set(setlist.songIDs)
        return visibleColorColumns(songs.filter { ids.contains($0.id) }, colorMode: colorMode)
    }

    private var hasSets: Bool {
        !setlist.setBreaks.isEmpty
    }

    var body: some View {
        let songsByID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let allRows = rows
        let counts = Dictionary(grouping: allRows.filter { if case .song = $0.item { return true } else { return false } }, by: \.setNumber).mapValues(\.count)

        VStack(spacing: 0) {
            header
            ColorColumnsHeader(colorMode: $colorMode, columns: columns, trailing: 16) { index in
                applyColor(index, to: songs.filter { checked.contains($0.id) })
            }
            .onChange(of: colorMode) { _, on in
                if !on { checked = [] }
            }
            Divider()
            // Egen lista (i stället för iPadens): håll in en rad och dra – en rosa linje
            // visar var raden hamnar.
            ScrollView {
                VStack(spacing: 0) {
                    if showsFirstHeader(allRows) {
                        SetHeaderRow(number: 1, count: counts[1] ?? 0, onRemove: nil)
                            .frame(height: Self.headerHeight)
                            .padding(.horizontal, 16)
                            .background(Self.tint(for: 1))
                    }
                    ForEach(allRows) { row in
                        rowView(row, songsByID: songsByID, counts: counts)
                            .overlay(alignment: .top) {
                                if dropTarget == row.id { DropLine() }
                            }
                            .dropDestination(for: String.self) { payloads, _ in
                                drop(payloads, before: row.id)
                            } isTargeted: { targeted in
                                target(row.id, targeted)
                            }
                    }
                    // Släpp nedanför sista raden = sist i listan.
                    let end = allRows.count
                    Color.clear
                        .frame(height: 80)
                        .contentShape(Rectangle())
                        .overlay(alignment: .top) {
                            if dropTarget == end { DropLine() }
                        }
                        .dropDestination(for: String.self) { payloads, _ in
                            drop(payloads, before: end)
                        } isTargeted: { targeted in
                            target(end, targeted)
                        }
                }
            }
            .overlay {
                if setlist.songIDs.isEmpty {
                    ContentUnavailableView(
                        "Listan är tom",
                        systemImage: "music.note.list",
                        description: Text("Tryck på \"+ Låtar\" för att lägga till låtar.")
                    )
                }
            }
        }
        .sheet(isPresented: $showAddSongs) {
            AddSongsSheet(setlist: setlist)
        }
        // Nästa/förra låt följer den här listan när man valt en låt ur den.
        .onAppear {
            // Låtlistans låtar ritas färdiga före resten av biblioteket.
            let ids = Set(setlist.songIDs)
            let byID = Dictionary(songs.filter { ids.contains($0.id) }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            PDFPageRenderer.shared.prepare(setlist.songIDs.compactMap { byID[$0] }.filter { $0.kind == .pdf }.map(\.fileURL), first: true)
            if let song = selection, setlist.songIDs.contains(song.id) {
                player.queue = setlist.songIDs
                player.setlistSongIDs = setlist.songIDs
            }
        }
        .onChange(of: selection) { _, song in
            if let song, song.id != player.playingSuggestionID, setlist.songIDs.contains(song.id) {
                player.queue = setlist.songIDs
                player.setlistSongIDs = setlist.songIDs
            }
        }
        .onChange(of: setlist.songIDs) { _, ids in
            if let song = selection, ids.contains(song.id) {
                player.queue = ids
                player.setlistSongIDs = ids
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 36, height: 40)
            }
            .accessibilityLabel("Alla låtlistor")
            Text(setlist.name)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 4)
            if !player.isLocked {
                editButtons
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var editButtons: some View {
        Button {
            setlist.items.append(.setBreak)
            try? context.save()
        } label: {
            Text("+ Set")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        Button {
            showAddSongs = true
        } label: {
            Text("+ Låtar")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        Menu {
            Button(action: onRename) { Label("Byt namn", systemImage: "pencil") }
            Button(action: onDuplicate) { Label("Duplicera", systemImage: "plus.square.on.square") }
            Button(role: .destructive, action: onDelete) { Label("Ta bort låtlistan", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .frame(width: 36, height: 40)
        }
        .accessibilityLabel("Fler val")
    }

    static let songHeight: CGFloat = 50
    static let headerHeight: CGFloat = 44

    private func showsFirstHeader(_ rows: [Row]) -> Bool {
        hasSets && (rows.first.map { $0.item != .setBreak } ?? false)
    }

    /// Ett drag börjar: kom ihåg vilken rad som dras.
    private func dragProvider(for row: Row, payload: String) -> NSItemProvider {
        dragging = row.id
        draggingPayload = payload
        return NSItemProvider(object: payload as NSString)
    }

    private func target(_ index: Int, _ targeted: Bool) {
        if targeted {
            dropTarget = index
        } else if dropTarget == index {
            dropTarget = nil
        }
    }

    /// Släpp före raden `index`: en rad ur listan flyttas, en låt från biblioteket läggs till.
    private func drop(_ payloads: [String], before index: Int) -> Bool {
        let from = dragging
        let payload = draggingPayload
        dragging = nil
        draggingPayload = nil
        dropTarget = nil
        guard !player.isLocked, let first = payloads.first else { return false }
        var items = setlist.items
        if let from, first == payload {
            guard items.indices.contains(from) else { return false }
            if index == from || index == from + 1 { return true }
            items.move(fromOffsets: IndexSet(integer: from), toOffset: index)
        } else {
            guard first.hasPrefix("song:"), let id = UUID(uuidString: String(first.dropFirst(5))) else { return false }
            items.insert(.song(id), at: min(index, items.count))
        }
        withAnimation(.easeOut(duration: 0.2)) {
            setlist.items = items
        }
        try? context.save()
        return true
    }

    @ViewBuilder
    private func rowView(_ row: Row, songsByID: [UUID: Song], counts: [Int: Int]) -> some View {
        switch row.item {
        case .setBreak:
            SetHeaderRow(number: row.setNumber, count: counts[row.setNumber] ?? 0, onRemove: removeAction(at: row.id))
                .frame(height: Self.headerHeight)
                .padding(.horizontal, 16)
                .background(Self.tint(for: row.setNumber))
                .contentShape(Rectangle())
                // Håll in och dra för att flytta setgränsen.
                .onDrag { dragProvider(for: row, payload: "setbreak:\(row.id)") }
        case .song(let id):
            HStack(spacing: 8) {
                if let song = songsByID[id] {
                    if colorMode {
                        ColorModeCheckbox(isChecked: checked.contains(song.id)) {
                            if checked.contains(song.id) { checked.remove(song.id) } else { checked.insert(song.id) }
                        }
                    }
                    Button {
                        player.startSwitchTimer()
                        selection = song
                    } label: {
                        SetSongRow(number: row.number, song: song, isPlayed: player.isPlayedTonight(song))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // Håll in och dra: flytta i listan, eller till Lådan i låtvyn.
                    .onDrag { dragProvider(for: row, payload: "song:\(song.id.uuidString)") }
                    ColorDots(song: song, editable: colorMode, columns: columns)
                } else {
                    Text("Låten finns inte längre i biblioteket")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 16)
            .frame(height: Self.songHeight)
            .background(rowBackground(row, songsByID[id]))
            // Svep åt vänster = ta bort ur listan, åt höger = lägg i Lådan.
            .modifier(SwipeRow(
                canDelete: !player.isLocked,
                onDelete: { remove(at: row.id) },
                onFullSwipeRight: songsByID[id].map { song in
                    {
                        player.drawerSongID = song.id
                        withAnimation(.spring(response: 0.55, dampingFraction: 1)) { player.drawerOpen = true }
                    }
                },
                leading: { close in
                    if let song = songsByID[id] {
                        SwipeButton(title: "Lådan", systemImage: "tray.and.arrow.down", color: .accentColor) {
                            close()
                            player.drawerSongID = song.id
                            withAnimation(.spring(response: 0.55, dampingFraction: 1)) { player.drawerOpen = true }
                        }
                    }
                }
            ))
            .overlay(alignment: .bottom) {
                Divider().padding(.leading, 16)
            }
            .contextMenu {
                if let song = songsByID[id] {
                    Button {
                        player.drawerSongID = song.id
                        withAnimation(.spring(response: 0.55, dampingFraction: 1)) { player.drawerOpen = true }
                    } label: {
                        Label("Lägg i lådan", systemImage: "tray.and.arrow.down")
                    }
                    PinButton(songID: song.id)
                    if !player.isLocked {
                        Button {
                            player.renamingSongID = song.id
                        } label: {
                            Label("Byt namn", systemImage: "pencil")
                        }
                    }
                }
                removeMenu(at: row.id)
            }
        }
    }

    private func rowBackground(_ row: Row, _ song: Song?) -> Color {
        if let song, selection == song { return Color.accentColor.opacity(0.35) }
        return hasSets ? Self.tint(for: row.setNumber) : .clear
    }

    @ViewBuilder
    private func removeMenu(at index: Int) -> some View {
        if !player.isLocked {
            Button(role: .destructive) {
                remove(at: index)
            } label: {
                Label("Ta bort ur listan", systemImage: "minus.circle")
            }
        }
    }

    /// × på setgränsen – av när scenlåset är på.
    private func removeAction(at index: Int) -> (() -> Void)? {
        player.isLocked ? nil : { remove(at: index) }
    }

    private func remove(at index: Int) {
        var items = setlist.items
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        setlist.items = items
        try? context.save()
    }

    /// Varje set har en svag egen färgton så att seten syns isär.
    /// Ordningen är vald så att två set i rad aldrig får snarlika färger
    /// (rosa, turkos, orange, blå, grön, gul – och sedan om från början).
    static func tint(for setNumber: Int) -> Color {
        let colors: [Color] = [Color.accentColor, .teal, .orange, .blue, .green, .yellow]
        return colors[(setNumber - 1) % colors.count].opacity(0.16)
    }
}

/// Den rosa linjen som visar var en dragen låt hamnar.
private struct DropLine: View {
    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 4)
            .padding(.horizontal, 4)
            .offset(y: -2)
            .allowsHitTesting(false)
    }
}

/// Rubrik för ett set: "SET 2 · 5 låtar", med × för att ta bort gränsen.
private struct SetHeaderRow: View {
    let number: Int
    let count: Int
    let onRemove: (() -> Void)?

    var body: some View {
        HStack {
            Text("SET \(number)")
                .font(.system(size: 14, weight: .bold))
                .tracking(1)
            Text(count == 1 ? "1 låt" : "\(count) låtar")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Ta bort setgränsen")
            }
        }
        .padding(.top, 6)
    }
}

private struct SetSongRow: View {
    let number: Int
    let song: Song
    let isPlayed: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 22, alignment: .trailing)
            Text(song.title)
                .lineLimit(1)
                .foregroundStyle(isPlayed ? .secondary : .primary)
            if song.kind == .note {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Anteckning")
            }
            Spacer(minLength: 0)
            if isPlayed {
                Text("spelad")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let key = song.displayKey {
                Text(key)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
