import SwiftData
import SwiftUI

/// Fliken Låtlistor: alla listor, eller den lista som är öppen.
struct SetlistsView: View {
    @Environment(\.modelContext) private var context
    @Query private var setlists: [Setlist]
    @Binding var selection: Song?

    @AppStorage("openSetlistID") private var openID = ""
    @State private var naming: Naming?
    @State private var nameDraft = ""
    @State private var deleting: Setlist?

    /// Vad namnrutan används till.
    private enum Naming: Identifiable {
        case create
        case rename(Setlist)

        var id: String {
            switch self {
            case .create: return "create"
            case .rename(let list): return list.id.uuidString
            }
        }
    }

    private var sorted: [Setlist] {
        setlists.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            if let open = setlists.first(where: { $0.id.uuidString == openID }) {
                SetlistDetailView(
                    setlist: open,
                    selection: $selection,
                    onClose: { openID = "" },
                    onRename: { startRename(open) },
                    onDuplicate: { duplicate(open) },
                    onDelete: { deleting = open }
                )
            } else {
                allLists
            }
        }
        .alert(namingTitle, isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Namn", text: $nameDraft)
            Button("Avbryt", role: .cancel) {}
            Button("Spara") { saveName() }
        }
        .confirmationDialog(
            "Ta bort \"\(deleting?.name ?? "")\"?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Ta bort låtlistan", role: .destructive) {
                if let list = deleting { delete(list) }
            }
        } message: {
            Text("Låtarna finns kvar i biblioteket.")
        }
    }

    private var allLists: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Alla låtlistor")
                    .font(.headline)
                Spacer()
                Button {
                    nameDraft = ""
                    naming = .create
                } label: {
                    Label("Ny lista", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            List {
                ForEach(sorted) { list in
                    Button {
                        openID = list.id.uuidString
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(list.name)
                                    .lineLimit(1)
                                Text(list.songIDs.count == 1 ? "1 låt" : "\(list.songIDs.count) låtar")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleting = list
                        } label: {
                            Label("Ta bort", systemImage: "trash")
                        }
                        Button {
                            duplicate(list)
                        } label: {
                            Label("Duplicera", systemImage: "plus.square.on.square")
                        }
                        .tint(.indigo)
                    }
                    .contextMenu {
                        Button { startRename(list) } label: { Label("Byt namn", systemImage: "pencil") }
                        Button { duplicate(list) } label: { Label("Duplicera", systemImage: "plus.square.on.square") }
                        Button(role: .destructive) { deleting = list } label: { Label("Ta bort", systemImage: "trash") }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if setlists.isEmpty {
                    ContentUnavailableView(
                        "Inga låtlistor ännu",
                        systemImage: "list.bullet",
                        description: Text("Tryck på \"Ny lista\" för att skapa en.")
                    )
                }
            }
        }
    }

    private var namingTitle: String {
        if case .rename? = naming { return "Byt namn" }
        return "Ny låtlista"
    }

    private func startRename(_ list: Setlist) {
        nameDraft = list.name
        naming = .rename(list)
    }

    private func saveName() {
        let name = nameDraft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        switch naming {
        case .create:
            let list = Setlist(name: name)
            context.insert(list)
            openID = list.id.uuidString
        case .rename(let list):
            list.name = name
        case nil:
            break
        }
        try? context.save()
        naming = nil
    }

    /// En kopia med samma låtar i samma ordning, som sedan kan ändras fritt.
    private func duplicate(_ list: Setlist) {
        let copy = Setlist(name: list.name + " (kopia)", songIDs: list.songIDs, setBreaks: list.setBreaks)
        context.insert(copy)
        try? context.save()
        openID = copy.id.uuidString
        startRename(copy)
    }

    private func delete(_ list: Setlist) {
        if openID == list.id.uuidString { openID = "" }
        context.delete(list)
        try? context.save()
        deleting = nil
    }
}
