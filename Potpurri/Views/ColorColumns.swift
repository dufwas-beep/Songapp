import SwiftUI

/// Rubriken ovanför färgkolumnerna: knappen "Färger" (färgläge) och färgernas namn.
/// I färgläget: tryck på en rubrik = ge alla ikryssade låtar färgen (eller ta bort den
/// om alla redan har den). Håll in en rubrik för att byta namn på färgen.
struct ColorColumnsHeader: View {
    @Binding var colorMode: Bool
    let onColumnTap: (Int) -> Void

    @Environment(ColorCodes.self) private var codes
    @Environment(Player.self) private var player
    @State private var renaming: Int?
    @State private var draft = ""

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
            Spacer()
            ForEach(0..<ColorCodes.count, id: \.self) { index in
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

/// En låts prickar i färgkolumnerna. I färgläget tänder/släcker ett tryck färgen.
struct ColorDots: View {
    static let columnWidth: CGFloat = 22
    let song: Song
    let editable: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<ColorCodes.count, id: \.self) { index in
                let isOn = song.colorTags.contains(index)
                ZStack {
                    if isOn {
                        Circle().fill(ColorCodes.colors[index]).frame(width: 11, height: 11)
                    } else if editable {
                        Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1.5).frame(width: 11, height: 11)
                    }
                }
                .frame(width: Self.columnWidth, height: 32)
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

/// Ge alla markerade låtar färgen – eller ta bort den om alla redan har den.
@MainActor
func applyColor(_ index: Int, to songs: [Song]) {
    guard !songs.isEmpty else { return }
    let allHave = songs.allSatisfy { $0.colorTags.contains(index) }
    for song in songs where song.colorTags.contains(index) == allHave {
        song.toggleColor(index)
    }
}
