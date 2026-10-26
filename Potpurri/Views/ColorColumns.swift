import SwiftUI

/// Rubriken ovanför färgkolumnerna: knappen "Färger" (färgläge) och färgernas namn.
/// I färgläget: tryck på en rubrik = ge alla ikryssade låtar färgen (eller ta bort den
/// om alla redan har den). Håll in en rubrik för att byta namn på färgen.
struct ColorColumnsHeader: View {
    @Binding var colorMode: Bool
    /// Kolumnerna som visas (se `visibleColorColumns`).
    let columns: [Int]
    let onColumnTap: (Int) -> Void

    @Environment(ColorCodes.self) private var codes
    @Environment(Player.self) private var player
    @State private var renaming: Int?
    @State private var draft = ""
    @State private var showsNames = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Button {
                withAnimation { colorMode.toggle() }
            } label: {
                Label(colorMode ? "Klar" : "Färger", systemImage: colorMode ? "checkmark" : "paintpalette")
                    .font(.footnote.weight(.medium))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(colorMode ? .accentColor : .secondary)
            .disabled(player.isLocked)
            .padding(.bottom, 4)
            if colorMode {
                Button {
                    showsNames = true
                } label: {
                    Label("Byt namn", systemImage: "pencil")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .padding(.leading, 6)
                .padding(.bottom, 4)
            }
            Spacer()
            ForEach(columns, id: \.self) { index in
                VStack(spacing: 4) {
                    Text(codes.names[index])
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .rotationEffect(.degrees(-90))
                        .frame(width: ColorDots.columnWidth, height: 58, alignment: .center)
                    Capsule()
                        .fill(ColorCodes.colors[index])
                        .frame(width: 16, height: 3)
                }
                .overlay(alignment: .leading) { ColumnLine() }
                .contentShape(Rectangle())
                .onTapGesture {
                    if colorMode { onColumnTap(index) }
                }
                .onLongPressGesture {
                    guard !player.isLocked else { return }
                    draft = codes.names[index]
                    renaming = index
                }
                .accessibilityLabel("Färgkod \(codes.names[index])")
                .accessibilityHint("Håll in för att byta namn")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 20)
        .sheet(isPresented: $showsNames) {
            ColorNamesSheet()
        }
        .alert("Byt namn på färgen", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
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

/// Byt namn på alla fem färgerna på ett ställe.
struct ColorNamesSheet: View {
    @Environment(ColorCodes.self) private var codes
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(drafts.indices, id: \.self) { index in
                        HStack(spacing: 12) {
                            Circle().fill(ColorCodes.colors[index]).frame(width: 18, height: 18)
                            TextField("Namn", text: $drafts[index])
                        }
                    }
                } footer: {
                    Text("Namnen visas överst i färgkolumnerna och i förslagsrutan.")
                }
            }
            .navigationTitle("Färgernas namn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara") {
                        for (index, draft) in drafts.enumerated() {
                            let name = draft.trimmingCharacters(in: .whitespaces)
                            if !name.isEmpty { codes.names[index] = name }
                        }
                        dismiss()
                    }
                }
            }
            .onAppear { drafts = codes.names }
        }
    }
}

/// En låts prickar i färgkolumnerna. I färgläget tänder/släcker ett tryck färgen.
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
        .accessibilityLabel(song.colorTags.isEmpty ? "Inga färgkoder" : "\(song.colorTags.count) färgkoder")
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

/// Kryssruta framför låten i färgläget.
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

/// Bara färger som någon låt har får en kolumn. I färgläget visas alla fem,
/// så att man kan börja använda en ny färg.
func visibleColorColumns(_ songs: [Song], colorMode: Bool) -> [Int] {
    if colorMode { return Array(0..<ColorCodes.count) }
    return Set(songs.flatMap(\.colorTags)).sorted()
}

/// Ge alla markerade låtar färgen – eller ta bort den om alla redan har den.
@MainActor
func applyColor(_ index: Int, to songs: [Song]) {
    guard !songs.isEmpty else { return }
    let allHave = songs.allSatisfy { $0.colorTags.contains(index) }
    for song in songs where song.colorTags.contains(index) == allHave {
        song.toggleColor(index)
    }
}
