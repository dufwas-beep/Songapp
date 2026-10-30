import SwiftData
import SwiftUI

/// Rubriken ovanför kategorikolumnerna: knappen "Markera" (markeringsläget, där man
/// kryssar i flera låtar och ger dem kategorier, tar bort dem m.m.) och namnen.
/// Vanligt läge: tryck på en rubrik = visa bara låtar i den kategorin (som i Next).
/// Kategoriläget: tryck på en rubrik = ge alla ikryssade låtar kategorin (eller ta bort
/// den om alla redan har den). Håll in en rubrik för att byta namn.
struct ColorColumnsHeader: View {
    @Binding var colorMode: Bool
    /// Kolumnerna som visas (se `visibleColorColumns`).
    let columns: [Int]
    /// Avståndet till högerkanten – samma som raderna under, så att kolumnerna linjerar.
    var trailing: CGFloat = 20
    /// Kategorierna man filtrerar på (tom = alla låtar).
    @Binding var filter: Set<Int>
    let onColumnTap: (Int) -> Void

    @Environment(ColorCodes.self) private var codes
    @Environment(Player.self) private var player
    @State private var renaming: Int?
    @State private var draft = ""
    @State private var showsNames = false
    @State private var confirmsClear = false
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Button {
                withAnimation { colorMode.toggle() }
            } label: {
                Label(colorMode ? "Klar" : "Markera", systemImage: colorMode ? "checkmark" : "checkmark.circle")
                    .font(.footnote.weight(.medium))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(colorMode ? .accentColor : .secondary)
            .disabled(player.isLocked)
            .guideSpot(.categories)
            .padding(.bottom, 4)
            if colorMode {
                Button {
                    showsNames = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .padding(.leading, 6)
                .padding(.bottom, 4)
                .accessibilityLabel("Kategoriernas namn och antal")
                Button(role: .destructive) {
                    confirmsClear = true
                } label: {
                    Image(systemName: "eraser")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .padding(.leading, 6)
                .padding(.bottom, 4)
                .accessibilityLabel("Rensa alla kategorier")
            }
            Spacer()
            ForEach(columns, id: \.self) { index in
                let isOn = filter.contains(index)
                VStack(spacing: 4) {
                    Text(codes.names[index])
                        .font(.system(size: 10, weight: isOn ? .bold : .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .rotationEffect(.degrees(-90))
                        .frame(width: ColorDots.columnWidth, height: 58, alignment: .center)
                    Capsule()
                        .fill(ColorCodes.colors[index])
                        .frame(width: 16, height: 3)
                }
                .background(isOn && !colorMode ? ColorCodes.colors[index].opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .opacity(filter.isEmpty || isOn || colorMode ? 1 : 0.4)
                .overlay(alignment: .leading) { ColumnLine() }
                .contentShape(Rectangle())
                .onTapGesture {
                    if colorMode {
                        onColumnTap(index)
                    } else if isOn {
                        filter.remove(index)
                    } else {
                        filter.insert(index)
                    }
                }
                .onLongPressGesture {
                    guard !player.isLocked else { return }
                    draft = codes.names[index]
                    renaming = index
                }
                .accessibilityLabel("Kategori \(codes.names[index])")
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                .accessibilityHint(colorMode ? "Ger de markerade låtarna kategorin" : "Visar bara låtar i kategorin. Håll in för att byta namn")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, trailing)
        .sheet(isPresented: $showsNames) {
            ColorNamesSheet()
        }
        .confirmationDialog("Ta bort alla kategorimarkeringar?", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("Rensa alla kategorier", role: .destructive) { clearAllColors() }
        } message: {
            Text("Alla låtar i hela biblioteket blir utan kategorier. Det går inte att ångra.")
        }
        .alert("Byt namn på kategorin", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Namn", text: $draft)
            Button("Avbryt", role: .cancel) {}
            Button("Spara") {
                let name = draft.trimmingCharacters(in: .whitespaces)
                if let index = renaming, !name.isEmpty { codes.names[index] = name }
                renaming = nil
            }
        }
    }
}

extension ColorColumnsHeader {
    /// Tar bort alla kategorimarkeringar från alla låtar.
    private func clearAllColors() {
        let all = (try? context.fetch(FetchDescriptor<Song>())) ?? []
        for song in all where !song.colorTags.isEmpty {
            song.colorTags = []
        }
        try? context.save()
        player.activeColors = []
        filter = []
    }
}

/// Visas när listan är filtrerad på kategorier: tydligt att alla låtar inte syns, och
/// en knapp som tar tillbaka hela listan.
struct CategoryFilterBar: View {
    let filter: Set<Int>
    let shown: Int
    let total: Int
    let onClear: () -> Void
    @Environment(ColorCodes.self) private var codes

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 0) {
                Text("Bara " + filter.sorted().map { codes.names[$0] }.joined(separator: ", "))
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Text("\(shown) av \(total) låtar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Visa alla", action: onClear)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .foregroundStyle(.black)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.18))
    }
}

/// I kategoriläget: vad som ska göras med de ikryssade låtarna.
struct CheckedActionsBar: View {
    let checkedCount: Int
    let totalCount: Int
    let onSelectAll: () -> Void
    let onSelectNone: () -> Void
    let onCategory: (Int) -> Void
    let onAddToSetlist: (Setlist) -> Void
    /// T.ex. "Ta bort" (biblioteket) eller "Ta bort ur listan" (en låtlista).
    let deleteTitle: String
    let onDelete: () -> Void
    /// Dela de markerade låtarna (AirDrop m.m.).
    var onShare: (() -> Void)?

    @Environment(ColorCodes.self) private var codes
    @Query private var setlists: [Setlist]
    @State private var confirmsDelete = false

    var body: some View {
        HStack(spacing: 8) {
            Text(checkedCount == 0 ? "Kryssa i låtar" : "\(checkedCount) markerade")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(checkedCount == 0 ? .secondary : .primary)
            Spacer(minLength: 4)
            Button(checkedCount == totalCount && totalCount > 0 ? "Avmarkera" : "Markera alla") {
                if checkedCount == totalCount && totalCount > 0 { onSelectNone() } else { onSelectAll() }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            // Ta bort ligger synligt – det man oftast vill göra med flera låtar.
            Button(role: .destructive) {
                confirmsDelete = true
            } label: {
                // Kort text så att raden får plats; frågan säger exakt vad som händer.
                Label("Ta bort", systemImage: "trash")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(.red)
            .disabled(checkedCount == 0)
            Menu {
                Menu {
                    ForEach(0..<codes.count, id: \.self) { index in
                        Button {
                            onCategory(index)
                        } label: {
                            Label(codes.names[index], systemImage: "circle.fill")
                        }
                    }
                } label: {
                    Label("Kategori", systemImage: "tag")
                }
                Menu {
                    ForEach(setlists.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { list in
                        Button(list.name) { onAddToSetlist(list) }
                    }
                } label: {
                    Label("Lägg i låtlista", systemImage: "text.badge.plus")
                }
                .disabled(setlists.isEmpty)
                if let onShare {
                    Button(action: onShare) {
                        Label("Dela (AirDrop …)", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Label("Mer", systemImage: "ellipsis.circle")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .foregroundStyle(.black)
            .disabled(checkedCount == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12))
        .confirmationDialog(
            checkedCount == 1 ? "\(deleteTitle): 1 låt?" : "\(deleteTitle): \(checkedCount) låtar?",
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button(deleteTitle, role: .destructive, action: onDelete)
        }
    }
}

/// Kategoriernas namn och hur många som används (upp till sju, fem rekommenderas).
struct ColorNamesSheet: View {
    @Environment(ColorCodes.self) private var codes
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [String] = []
    @State private var count = ColorCodes.recommendedCount

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $count, in: 1...ColorCodes.maxCount) {
                        Text("Antal kategorier: \(count)")
                    }
                } footer: {
                    Text("Upp till \(ColorCodes.maxCount). \(ColorCodes.recommendedCount) rekommenderas – då får kolumnerna plats bredvid låtnamnen.")
                }
                Section {
                    ForEach(0..<min(count, drafts.count), id: \.self) { index in
                        HStack(spacing: 12) {
                            Circle().fill(ColorCodes.colors[index]).frame(width: 18, height: 18)
                            TextField("Namn", text: $drafts[index])
                        }
                    }
                } footer: {
                    Text("Namnen visas överst i kolumnerna och i Next.")
                }
            }
            .navigationTitle("Kategorier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara") {
                        var names = codes.names
                        for (index, draft) in drafts.enumerated() where index < names.count {
                            let name = draft.trimmingCharacters(in: .whitespaces)
                            if !name.isEmpty { names[index] = name }
                        }
                        codes.names = names
                        codes.count = count
                        dismiss()
                    }
                }
            }
            .onAppear {
                drafts = codes.names
                count = codes.count
            }
        }
    }
}

/// En låts prickar i kategorikolumnerna. I kategoriläget tänder/släcker ett tryck kategorin.
struct ColorDots: View {
    static let columnWidth: CGFloat = 22
    let song: Song
    let editable: Bool
    let columns: [Int]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(columns, id: \.self) { index in
                let isOn = song.colorTags.contains(index)
                ZStack {
                    if isOn {
                        Circle().fill(ColorCodes.colors[index]).frame(width: 11, height: 11)
                    } else if editable {
                        Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1.5).frame(width: 11, height: 11)
                    }
                }
                .frame(width: Self.columnWidth, height: 32)
                .overlay(alignment: .leading) { ColumnLine().padding(.vertical, -14) }
                .contentShape(Rectangle())
                .onTapGesture {
                    if editable { song.toggleColor(index) }
                }
                .allowsHitTesting(editable)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(song.colorTags.isEmpty ? "Inga kategorier" : "\(song.colorTags.count) kategorier")
    }
}

/// Tunn linje mellan färgkolumnerna. Går lite utanför raden så att linjerna hänger ihop.
private struct ColumnLine: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(width: 1)
            .allowsHitTesting(false)
    }
}

/// Kryssruta framför låten i kategoriläget.
struct ColorModeCheckbox: View {
    let isChecked: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isChecked ? "Avmarkera" : "Markera")
    }
}

/// Bara kategorier som någon låt har får en kolumn. I kategoriläget visas alla som
/// används (`count`), så att man kan börja använda en ny.
func visibleColorColumns(_ songs: [Song], colorMode: Bool, count: Int) -> [Int] {
    if colorMode { return Array(0..<count) }
    return Set(songs.flatMap(\.colorTags)).filter { $0 < count }.sorted()
}

/// Ge alla markerade låtar kategorin – eller ta bort den om alla redan har den.
@MainActor
func applyColor(_ index: Int, to songs: [Song]) {
    guard !songs.isEmpty else { return }
    let allHave = songs.allSatisfy { $0.colorTags.contains(index) }
    for song in songs where song.colorTags.contains(index) == allHave {
        song.toggleColor(index)
    }
}
