import SwiftData
import SwiftUI

/// En öppen låtlista: låtarna i ordning, indelade i set med setgränser.
/// Håll in en låt eller setgräns så lossnar den och följer fingret; släpp där den ska
/// ligga. Håll in och släpp utan att dra för att ta bort en låt ur listan.
struct SetlistDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var setlist: Setlist
    @Query private var songs: [Song]
    @Binding var selection: Song?
    let onClose: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @State private var showAddSongs = false

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

    private var hasSets: Bool {
        !setlist.setBreaks.isEmpty
    }

    var body: some View {
        let songsByID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let allRows = rows
        let counts = Dictionary(grouping: allRows.filter { if case .song = $0.item { return true } else { return false } }, by: \.setNumber).mapValues(\.count)

        VStack(spacing: 0) {
            header
            List(selection: $selection) {
                if hasSets, allRows.first.map({ $0.item != .setBreak }) ?? false {
                    SetHeaderRow(number: 1, count: counts[1] ?? 0, onRemove: nil)
                        .selectionDisabled()
                        .listRowBackground(Self.tint(for: 1))
                        .moveDisabled(true)
                }
                ForEach(allRows) { row in
                    switch row.item {
                    case .setBreak:
                        SetHeaderRow(number: row.setNumber, count: counts[row.setNumber] ?? 0) {
                            remove(at: row.id)
                        }
                        .selectionDisabled()
                        .draggable("row:\(row.id)") { DragPreview(title: "Set \(row.setNumber)") }
                        .listRowBackground(Self.tint(for: row.setNumber))
                    case .song(let id):
                        if let song = songsByID[id] {
                            SetSongRow(number: row.number, song: song)
                                .tag(song)
                                .draggable("row:\(row.id)") { DragPreview(title: song.title) }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        remove(at: row.id)
                                    } label: {
                                        Label("Ta bort ur listan", systemImage: "minus.circle")
                                    }
                                }
                                .listRowBackground(selection == song ? Color.accentColor.opacity(0.35) : (hasSets ? Self.tint(for: row.setNumber) : nil))
                        } else {
                            Text("Låten finns inte längre i biblioteket")
                                .foregroundStyle(.secondary)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        remove(at: row.id)
                                    } label: {
                                        Label("Ta bort ur listan", systemImage: "minus.circle")
                                    }
                                }
                        }
                    }
                }
                .dropDestination(for: String.self) { payloads, offset in
                    drop(payloads, at: offset)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
        withAnimation {
            setlist.items = items
        }
        try? context.save()
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
            Spacer(minLength: 0)
            if let key = song.key {
                Text(key)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
