import SwiftData
import SwiftUI

/// En öppen låtlista: låtarna i ordning, indelade i set med setgränser.
/// Håll in en låt eller setgräns så lossnar den och följer fingret; släpp där den ska
/// ligga. Håll in och släpp utan att dra för att ta bort en låt ur listan.
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
    /// Raden som en dragen låt just nu hänger över (där den rosa linjen visas).
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

    /// Färgkolumnerna – bara färger som någon låt i biblioteket har (alla i färgläget).
    private var columns: [Int] {
        visibleColorColumns(songs, colorMode: colorMode)
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
            ColorColumnsHeader(colorMode: $colorMode, columns: columns) { index in
                applyColor(index, to: songs.filter { checked.contains($0.id) })
            }
            .onChange(of: colorMode) { _, on in
                if !on { checked = [] }
            }
            Divider()
            List(selection: $selection) {
                if hasSets, allRows.first.map({ $0.item != .setBreak }) ?? false {
                    SetHeaderRow(number: 1, count: counts[1] ?? 0, onRemove: nil)
                        .selectionDisabled()
                        .listRowBackground(Self.tint(for: 1))
                        .moveDisabled(true)
                }
                ForEach(allRows) { row in
                    rowView(row, songsByID: songsByID, counts: counts)
                        // Släpp på en rad = lägg den dragna raden före den. En rosa linje visar var.
                        .dropDestination(for: String.self) { payloads, _ in
                            guard !player.isLocked else { return false }
                            drop(payloads, at: row.id)
                            return true
                        } isTargeted: { targeted in
                            if targeted {
                                dropTarget = row.id
                            } else if dropTarget == row.id {
                                dropTarget = nil
                            }
                        }
                        .overlay(alignment: .top) {
                            if dropTarget == row.id {
                                DropLine()
                            }
                        }
                }
                // Tom rad sist så att man kan släppa längst ner i listan.
                Color.clear
                    .frame(height: 56)
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
                    .moveDisabled(true)
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { payloads, _ in
                        guard !player.isLocked else { return false }
                        drop(payloads, at: allRows.count)
                        return true
                    } isTargeted: { targeted in
                        dropTarget = targeted ? allRows.count : (dropTarget == allRows.count ? nil : dropTarget)
                    }
                    .overlay(alignment: .top) {
                        if dropTarget == allRows.count {
                            DropLine()
                        }
                    }
            }
            .listStyle(.plain)
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
            if let song = selection, setlist.songIDs.contains(song.id) {
                player.queue = setlist.songIDs
            }
        }
        .onChange(of: selection) { _, song in
            if let song, song.id != player.playingSuggestionID, setlist.songIDs.contains(song.id) {
                player.queue = setlist.songIDs
            }
        }
        .onChange(of: setlist.songIDs) { _, ids in
            if let song = selection, ids.contains(song.id) {
                player.queue = ids
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

    @ViewBuilder
    private func rowView(_ row: Row, songsByID: [UUID: Song], counts: [Int: Int]) -> some View {
        switch row.item {
        case .setBreak:
            SetHeaderRow(number: row.setNumber, count: counts[row.setNumber] ?? 0, onRemove: removeAction(at: row.id))
                .selectionDisabled()
                .draggable("row:\(row.id)") { DragPreview(title: "Set \(row.setNumber)") }
                .listRowBackground(Self.tint(for: row.setNumber))
        case .song(let id):
            if let song = songsByID[id] {
                HStack(spacing: 8) {
                    if colorMode {
                        ColorModeCheckbox(isChecked: checked.contains(song.id)) {
                            if checked.contains(song.id) { checked.remove(song.id) } else { checked.insert(song.id) }
                        }
                    }
                    SetSongRow(number: row.number, song: song, isPlayed: player.isPlayedTonight(song))
                    ColorDots(song: song, editable: colorMode, columns: columns)
                }
                    .tag(song)
                    .draggable("row:\(row.id)") { DragPreview(title: song.title) }
                    .contextMenu {
                        PinButton(songID: song.id)
                        removeMenu(at: row.id)
                    }
                    .listRowBackground(selection == song ? Color.accentColor.opacity(0.35) : (hasSets ? Self.tint(for: row.setNumber) : nil))
            } else {
                Text("Låten finns inte längre i biblioteket")
                    .foregroundStyle(.secondary)
                    .contextMenu { removeMenu(at: row.id) }
            }
        }
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

    /// Släpp i listan: "row:3" flyttar en rad inom listan, "song:<id>" lägger in en låt.
    private func drop(_ payloads: [String], at offset: Int) {
        var items = setlist.items
        var target = min(max(offset, 0), items.count)
        for payload in payloads {
            if payload.hasPrefix("row:"), let index = Int(payload.dropFirst(4)), items.indices.contains(index) {
                items.move(fromOffsets: IndexSet(integer: index), toOffset: target)
                target = index < target ? target : target + 1
            } else if payload.hasPrefix("song:"), let id = UUID(uuidString: String(payload.dropFirst(5))) {
                items.insert(.song(id), at: target)
                target += 1
            }
        }
        dropTarget = nil
        withAnimation {
            setlist.items = items
        }
        try? context.save()
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
    static func tint(for setNumber: Int) -> Color {
        let colors: [Color] = [Color.accentColor, .purple, .teal, .orange, .blue]
        return colors[(setNumber - 1) % colors.count].opacity(0.08)
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

/// Det som följer fingret när en rad dras.
private struct DragPreview: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.body.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.black)
    }
}

/// Rubrik för ett set: "SET 2 · 5 låtar", med × för att ta bort gränsen.
private struct SetHeaderRow: View {
    let number: Int
    let count: Int
    let onRemove: (() -> Void)?

    var body: some View {
        HStack {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .opacity(onRemove == nil ? 0 : 1)
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
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
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
            if let key = song.key {
                Text(key)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
