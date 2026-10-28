import SwiftData
import SwiftUI

/// En ny låt skriven direkt i Potpurri: namn, text (skriv eller klistra in, t.ex. från
/// Anteckningar) och kategorier. Blir en textlåt som öppnas när den sparas.
struct NewSongSheet: View {
    let onAdded: (Song) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ColorCodes.self) private var codes
    @State private var title = ""
    @State private var text = ""
    @State private var categories: Set<Int> = []
    @FocusState private var titleFocused: Bool

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Låtens namn", text: $title)
                        .font(.title2.weight(.semibold))
                        .focused($titleFocused)
                    // Kategorierna – tryck för att välja.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(0..<codes.count, id: \.self) { index in
                                let isOn = categories.contains(index)
                                Button {
                                    if isOn { categories.remove(index) } else { categories.insert(index) }
                                } label: {
                                    HStack(spacing: 6) {
                                        Circle().fill(ColorCodes.colors[index]).frame(width: 10, height: 10)
                                        Text(codes.names[index])
                                            .font(.footnote.weight(isOn ? .semibold : .regular))
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(height: 30)
                                    .background(isOn ? ColorCodes.colors[index].opacity(0.25) : Color(.tertiarySystemFill), in: Capsule())
                                    .overlay(Capsule().stroke(isOn ? ColorCodes.colors[index] : .clear, lineWidth: 1.5))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(isOn ? .isSelected : [])
                            }
                        }
                    }
                    Text("Skriv eller klistra in texten. Ackord i hakparenteser, t.ex. Jag [G]går hem, eller på en egen rad ovanför texten. Markera text och tryck B (fet) eller I (kursiv).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
                StyledTextEditor(text: $text)
            }
            .navigationTitle("Ny låt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara", action: save)
                        .disabled(trimmedTitle.isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { titleFocused = true }
        }
    }

    private func save() {
        // Utan namn blir första raden namnet.
        let firstLine = text.components(separatedBy: .newlines)
            .map { InlineStyle.plain($0).trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "Ny låt"
        let name = trimmedTitle.isEmpty ? String(firstLine.prefix(60)) : trimmedTitle
        let song = Song(title: name, kind: .text, text: text)
        song.colorTags = categories.sorted()
        context.insert(song)
        try? context.save()
        onAdded(song)
        dismiss()
    }
}
