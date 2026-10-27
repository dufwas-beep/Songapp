import SwiftData
import SwiftUI

/// "Passar efter": låtar som passar efter den som spelas, styrda av färgerna man väljer.
/// Låtar som spelats under kvällen visas aldrig här. Tryck = öppna i förhandsrutan.
struct SuggestionsBox: View {
    let current: Song?
    @Query private var songs: [Song]
    @Environment(Player.self) private var player
    @Environment(ColorCodes.self) private var codes

    private var suggestions: [Song] {
        guard let current else { return [] }
        let colors = player.activeColors
        let available = songs.filter { $0.id != current.id && $0.kind != .note && !player.isPlayedTonight($0) }
        let pinned = player.pinned.compactMap { id in available.first { $0.id == id } }
        let matching = available
            .filter { !player.pinned.contains($0.id) && !colors.isDisjoint(with: $0.colorTags) }
            .sorted {
                let a = colors.intersection($0.colorTags).count
                let b = colors.intersection($1.colorTags).count
                return a != b ? a > b : Song.swedishOrder($0, $1)
            }
        // De 40 bästa räcker – färre rader gör rutan snabbare.
        return pinned + matching.prefix(40)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Samma färgrubriker som i låtlistan. Tryck på en rubrik för att välja om
            // färgen ska styra förslagen – valda färger är markerade.
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXT")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text(current == nil ? "Välj en låt" : (current?.colorTags.isEmpty == true ? "Låten har inga färger" : "Tryck på färgerna"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 4)
                Spacer()
                ForEach(current?.colorTags ?? [], id: \.self) { index in
                    let isOn = player.activeColors.contains(index)
                    VStack(spacing: 4) {
                        Text(codes.names[index])
                            .font(.system(size: 10, weight: isOn ? .bold : .medium))
                            .lineLimit(1)
                            .fixedSize()
                            .rotationEffect(.degrees(-90))
                            .frame(width: ColorDots.columnWidth, height: 58)
                        Capsule()
                            .fill(ColorCodes.colors[index])
                            .frame(width: 16, height: 3)
                    }
                    .background(isOn ? ColorCodes.colors[index].opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .opacity(isOn ? 1 : 0.4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isOn { player.activeColors.remove(index) } else { player.activeColors.insert(index) }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(codes.names[index])
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 20)
            .padding(.vertical, 8)
            Divider()
            let list = suggestions
            // Samma kolumner som rubrikerna ovanför.
            let columns = current?.colorTags ?? []
            List {
                ForEach(list) { song in
                    Button {
                        player.previewID = song.id
                    } label: {
                        HStack(spacing: 6) {
                            if player.pinned.contains(song.id) {
                                Image(systemName: "pin.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                            }
                            Text(song.title)
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            ColorDots(song: song, editable: false, columns: columns)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(player.lotteryHighlight == song.id ? Color.accentColor : (player.previewID == song.id ? Color.accentColor.opacity(0.25) : nil))
                    .contextMenu { PinButton(songID: song.id) }
                }
            }
            .listStyle(.plain)
            .overlay {
                if list.isEmpty, current != nil, !player.activeColors.isEmpty {
                    Text("Inga fler låtar med de färgerna ikväll.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        // Lyckohjulet: markeringen hoppar mellan förslagen, saktar in och landar på en
        // slumpad låt som öppnas i förhandsrutan. Spelade låtar finns aldrig med.
        .onChange(of: player.lotteryRuns) {
            let list = suggestions
            guard !list.isEmpty else { return }
            let target = Int.random(in: 0..<list.count)
            let hops = list.count * 2 + target
            Task {
                var delay = 0.04
                for hop in 0...hops {
                    player.lotteryHighlight = list[hop % list.count].id
                    try? await Task.sleep(for: .seconds(delay))
                    delay = min(delay * 1.12, 0.35)
                }
                player.previewID = list[target].id
                try? await Task.sleep(for: .seconds(0.6))
                player.lotteryHighlight = nil
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.2)))
    }
}

/// Fäst eller lossa en låt överst bland kvällens förslag.
struct PinButton: View {
    let songID: UUID
    @Environment(Player.self) private var player

    var body: some View {
        Button {
            player.togglePin(songID)
        } label: {
            if player.pinned.contains(songID) {
                Label("Ta bort från förslagen", systemImage: "pin.slash")
            } else {
                Label("Fäst bland förslagen", systemImage: "pin")
            }
        }
    }
}

/// Längst ner i sidospalten: "Ny spelning", hur många låtar som spelats ikväll och en
/// meny med kvällsloggar och säkerhetskopia.
struct GigFooter: View {
    @Query private var songs: [Song]
    @Environment(Player.self) private var player
    @Environment(ColorCodes.self) private var colorCodes
    @Environment(\.modelContext) private var context
    @State private var confirming = false
    @State private var showsLogs = false
    @State private var backupProgress = TaskProgress()
    @State private var exportedURL: URL?
    @State private var importing = false
    @State private var pendingRestore: (content: Backup.Content, archive: ZipArchive)?
    @State private var message: String?

    var body: some View {
        VStack(spacing: 8) {
            if backupProgress.isRunning {
                ProgressBanner(progress: backupProgress)
            }
            HStack(spacing: 12) {
                Button {
                    confirming = true
                } label: {
                    Text("Ny spelning")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .controlSize(.large)
                let count = songs.filter(player.isPlayedTonight).count
                Text(count == 1 ? "1 spelad" : "\(count) spelade")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Menu {
                    Button {
                        showsLogs = true
                    } label: {
                        Label("Kvällsloggar", systemImage: "music.note.list")
                    }
                    Divider()
                    Button {
                        Task { await export() }
                    } label: {
                        Label("Spara säkerhetskopia", systemImage: "externaldrive.badge.plus")
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("Läs in säkerhetskopia", systemImage: "externaldrive.badge.timemachine")
                    }
                    .disabled(player.isLocked)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                }
                .disabled(backupProgress.isRunning)
                .accessibilityLabel("Kvällsloggar och säkerhetskopia")
            }
        }
        .confirmationDialog("Starta en ny spelning?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Ny spelning") { player.newGig() }
        } message: {
            Text("Gråmarkeringar och fästa förslag nollställs, och en ny kvällslogg börjar.")
        }
        .sheet(isPresented: $showsLogs) {
            GigLogsView()
        }
        // Säkerhetskopian sparas där man väljer i Filer (t.ex. iCloud Drive eller Dropbox).
        .fileMover(isPresented: Binding(get: { exportedURL != nil }, set: { if !$0 { exportedURL = nil } }), file: exportedURL) { result in
            if case .success = result { message = "Säkerhetskopian är sparad." }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            guard case .success(let url) = result else { return }
            Task {
                do {
                    pendingRestore = try await Task.detached { try Backup.read(url) }.value
                } catch {
                    message = "Filen kunde inte läsas som en säkerhetskopia från Potpurri."
                }
            }
        }
        .confirmationDialog(
            "Ersätta allt med säkerhetskopian?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button("Ersätt allt", role: .destructive) {
                guard let pending = pendingRestore else { return }
                Task {
                    do {
                        try await Backup.restore(pending.content, archive: pending.archive, context: context, colorCodes: colorCodes, progress: backupProgress)
                        message = "Säkerhetskopian är inläst."
                    } catch {
                        message = "Det gick inte att läsa in säkerhetskopian: \(error.localizedDescription)"
                    }
                    pendingRestore = nil
                }
            }
        } message: {
            if let content = pendingRestore?.content {
                Text("Kopian från \(content.created.formatted(date: .abbreviated, time: .shortened)) har \(content.songs.count) låtar och \(content.setlists.count) låtlistor. Allt som finns i appen nu ersätts.")
            }
        }
        .alert("Säkerhetskopia", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func export() async {
        do {
            try context.save()
            exportedURL = try await Backup.export(context: context, colorNames: colorCodes.names, progress: backupProgress)
        } catch {
            message = "Säkerhetskopian kunde inte skapas: \(error.localizedDescription)"
        }
    }
}
