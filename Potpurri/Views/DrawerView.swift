import SwiftData
import SwiftUI

/// Lådan i högerkanten av låtvyn: ett handtag som dras ut till en låda med en låt eller
/// anteckning (t.ex. ett quizmanus). Rymmer en sak åt gången; en ny ersätter den gamla.
/// Låtar och anteckningar läggs dit genom att dras från listorna, eller "Lägg i lådan".
struct DrawerView: View {
    let width: CGFloat
    @Environment(Player.self) private var player
    @Environment(\.modelContext) private var context
    @Query private var songs: [Song]

    @State private var dragOffset: CGFloat = 0
    @State private var targeted = false
    @State private var writingNote = false

    private var item: Song? {
        guard let id = player.drawerSongID else { return nil }
        return songs.first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 0) {
            handle
            content
                .frame(width: width)
                .background(Color(.systemBackground))
                .overlay(alignment: .leading) { Divider() }
                .shadow(color: .black.opacity(player.drawerOpen ? 0.18 : 0), radius: 12, x: -4)
        }
        // Stängd: bara handtaget syns i kanten. Under drag följer lådan fingret.
        .offset(x: min(max((player.drawerOpen ? 0 : width) + dragOffset, 0), width))
        .frame(maxHeight: .infinity)
        .dropDestination(for: String.self) { payloads, _ in
            guard let id = payloads.compactMap(Self.songID).first else { return false }
            put(id)
            return true
        } isTargeted: { targeted = $0 }
        .sheet(isPresented: $writingNote) {
            if let item { DrawerNoteEditor(song: item) }
        }
    }

    /// "song:<uuid>" → låtens id.
    static func songID(_ payload: String) -> UUID? {
        guard payload.hasPrefix("song:") else { return nil }
        return UUID(uuidString: String(payload.dropFirst(5)))
    }

    private func put(_ id: UUID) {
        player.drawerSongID = id
        withAnimation(.spring(response: 0.55, dampingFraction: 1)) { player.drawerOpen = true }
    }

    /// Handtaget: tryck = öppna/stäng, dra åt vänster = dra ut, åt höger = skjut tillbaka.
    /// Lådan glider och bromsar mjukt och långsamt i slutet.
    private var handle: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.secondary.opacity(0.6))
            .frame(width: 5, height: 46)
            .frame(width: 34, height: 150)
            .background(targeted ? Color.accentColor.opacity(0.5) : Color(.secondarySystemBackground), in: UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16))
            .shadow(color: .black.opacity(0.15), radius: 6, x: -2)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.55, dampingFraction: 1)) { player.drawerOpen.toggle() }
            }
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in dragOffset = value.translation.width }
                    .onEnded { value in
                        let open = player.drawerOpen ? value.translation.width < width / 3 : value.translation.width < -width / 4
                        withAnimation(.spring(response: 0.6, dampingFraction: 1)) {
                            player.drawerOpen = open
                            dragOffset = 0
                        }
                    }
            )
            .accessibilityLabel(player.drawerOpen ? "Stäng lådan" : "Öppna lådan")
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                Text("LÅDAN")
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text(item?.title ?? "")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if let item, !player.isLocked {
                    writeMenu(for: item)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(targeted ? Color.accentColor.opacity(0.3) : Color.clear)
            Divider()
            if let item {
                if let note = item.drawerNote, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(uiColor: UIColor(hex: NoteColors.yellow)))
                        .onTapGesture { if !player.isLocked { writingNote = true } }
                        .accessibilityLabel("Mina anteckningar: \(note)")
                }
                SongSheetView(song: item) { _ in }
                    .id(item.id)
            } else {
                ContentUnavailableView(
                    "Lådan är tom",
                    systemImage: "tray",
                    description: Text("Dra hit en låt eller anteckning från listan, eller håll in den och välj \"Lägg i lådan\".")
                )
            }
        }
    }

    /// "Skriv": välj hur man vill skriva – i själva texten eller i ett gult fält.
    private func writeMenu(for item: Song) -> some View {
        Menu {
            if item.kind == .note {
                Button {
                    player.editingTextSongID = item.id
                } label: {
                    Label("Redigera texten", systemImage: "square.and.pencil")
                }
            } else if item.kind == .text {
                Button {
                    player.editingTextSongID = item.id
                } label: {
                    Label("Redigera låttexten", systemImage: "square.and.pencil")
                }
            } else if item.kind == .pdf {
                let hasText = !(item.searchText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !(PDFCache.shared.document(for: item.fileURL)?.string ?? "").isEmpty
                Button {
                    item.text = PDFCache.shared.document(for: item.fileURL)?.string ?? item.searchText ?? item.title
                    item.kindRaw = SongKind.text.rawValue
                    player.editingTextSongID = item.id
                } label: {
                    Label(hasText ? "Redigera låttexten" : "Redigera låttexten (PDF:en saknar text)", systemImage: "square.and.pencil")
                }
                .disabled(!hasText)
            } else {
                Button {} label: {
                    Label("Bilder kan inte redigeras som text", systemImage: "photo")
                }
                .disabled(true)
            }
            Button {
                writingNote = true
            } label: {
                Label("Skriv i gult fält", systemImage: "note.text")
            }
            if item.canRestorePDF {
                Button {
                    item.kindRaw = SongKind.pdf.rawValue
                } label: {
                    Label("Återställ PDF", systemImage: "arrow.uturn.backward")
                }
            }
        } label: {
            Label("Skriv", systemImage: "pencil")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
    }
}

/// Det gula fältet ("Mina anteckningar") ovanför låten i Lådan – själva låten ändras inte.
private struct DrawerNoteEditor: View {
    @Bindable var song: Song
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $draft)
                .font(.title3)
                .padding(12)
                .scrollContentBackground(.hidden)
                .background(Color(uiColor: UIColor(hex: NoteColors.yellow)).opacity(0.5))
                .navigationTitle("Mina anteckningar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Avbryt") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Klar") {
                            song.drawerNote = draft
                            dismiss()
                        }
                    }
                }
                .onAppear { draft = song.drawerNote ?? "" }
        }
    }
}
