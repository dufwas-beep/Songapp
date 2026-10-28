import SwiftData
import SwiftUI

/// Lägg till låtar i en låtlista (eller ett quiz): sök, kryssa i och tryck "Lägg till".
struct AddSongsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    /// Låtar som redan finns (visas gråa men går ändå att välja).
    let existing: [UUID]
    let onAdd: ([UUID]) -> Void
    @Query private var songs: [Song]

    init(title: String, existing: [UUID], onAdd: @escaping ([UUID]) -> Void) {
        self.title = title
        self.existing = existing
        self.onAdd = onAdd
    }

    init(setlist: Setlist) {
        self.init(title: "Lägg till i \(setlist.name)", existing: setlist.songIDs) { ids in
            setlist.songIDs.append(contentsOf: ids)
            try? setlist.modelContext?.save()
        }
    }

    @State private var query = ""
    @State private var selected: Set<UUID> = []

    private var visible: [Song] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let filtered = q.isEmpty ? songs : songs.filter { $0.title.localizedCaseInsensitiveContains(q) }
        return filtered.sorted(by: Song.swedishOrder)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(visible) { song in
                    Button {
                        if selected.contains(song.id) {
                            selected.remove(song.id)
                        } else {
                            selected.insert(song.id)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected.contains(song.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(selected.contains(song.id) ? Color.accentColor : Color.secondary)
                            // Låtar som redan finns i listan är gråa men går ändå att välja.
                            let alreadyIn = existing.contains(song.id)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title)
                                    .lineLimit(1)
                                    .foregroundStyle(alreadyIn ? .secondary : .primary)
                                if alreadyIn {
                                    Text("Finns redan i listan")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $query, prompt: "Sök låt")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lägg till \(selected.count)") {
                        // I bokstavsordning, oavsett i vilken ordning de kryssades i.
                        onAdd(songs.sorted(by: Song.swedishOrder).map(\.id).filter(selected.contains))
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Markera alla") {
                        selected.formUnion(visible.map(\.id))
                    }
                    Spacer()
                    Button("Avmarkera alla") {
                        selected.subtract(visible.map(\.id))
                    }
                }
            }
        }
    }
}
