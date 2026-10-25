import SwiftUI

/// Låten som spelas: låtbladet, autoscrollknappen i hörnet och nästa/förra låt.
/// Pedal och tangentbord: pil ner/höger, Page Down och mellanslag bläddrar framåt –
/// i slutet av låten kommer nästa låt. Pil upp/vänster och Page Up bläddrar bakåt.
struct SongDetailView: View {
    let song: Song?
    let previous: Song?
    let next: Song?
    let onSelect: (Song) -> Void

    @Environment(Player.self) private var player
    @State private var autoscroller = Autoscroller()
    @FocusState private var focused: Bool

    var body: some View {
        if let song {
            ZStack(alignment: .bottomTrailing) {
                songSheet(for: song)
                    .id(song.id)
                AutoscrollButton(autoscroller: autoscroller, seconds: secondsBinding(for: song))
                    .padding(24)
            }
            .overlay(alignment: .top) {
                if player.isLocked {
                    Label("Scenlås", systemImage: "lock.fill")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.black)
                        .padding(.top, 8)
                        .accessibilityLabel("Scenlåset är på")
                }
            }
            .navigationTitle(song.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        if let previous { onSelect(previous) }
                    } label: {
                        Label("Förra låten", systemImage: "chevron.left")
                    }
                    .disabled(previous == nil)
                    Button {
                        if let next { onSelect(next) }
                    } label: {
                        HStack(spacing: 4) {
                            if let next {
                                Text(next.title)
                                    .lineLimit(1)
                                    .frame(maxWidth: 220)
                            }
                            Image(systemName: "chevron.right")
                        }
                    }
                    .disabled(next == nil)
                    .accessibilityLabel(next.map { "Nästa låt: \($0.title)" } ?? "Ingen nästa låt")
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onKeyPress(keys: [.downArrow, .rightArrow, .pageDown, .space]) { _ in
                forward()
                return .handled
            }
            .onKeyPress(keys: [.upArrow, .leftArrow, .pageUp]) { _ in
                backward()
                return .handled
            }
            .task(id: song.id) {
                autoscroller.stop()
                autoscroller.duration = TimeInterval(song.autoscrollSeconds ?? 180)
                focused = true
                if let next, next.kind == .pdf { PDFCache.shared.preload(next.fileURL) }
                // En låt räknas som spelad när den varit öppen i 30 sekunder.
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                song.playCount += 1
                song.lastPlayed = Date()
            }
        } else {
            ContentUnavailableView(
                "Välj en låt",
                systemImage: "music.note",
                description: Text("Välj en låt i listan till vänster.")
            )
        }
    }

    @ViewBuilder
    private func songSheet(for song: Song) -> some View {
        let attach: (UIScrollView) -> Void = { autoscroller.attach($0) }
        if song.kind == .text || song.kind == .note {
            TextSongView(song: song, onScrollView: attach)
        } else if !FileManager.default.fileExists(atPath: song.fileURL.path) {
            ContentUnavailableView(
                "Filen saknas",
                systemImage: "exclamationmark.triangle",
                description: Text("Låtens fil hittades inte. Importera den igen.")
            )
        } else if song.kind == .pdf {
            PDFKitView(url: song.fileURL, onScrollView: attach)
        } else {
            ImageSongView(url: song.fileURL, onScrollView: attach)
        }
    }

    private func secondsBinding(for song: Song) -> Binding<Int> {
        Binding(
            get: { song.autoscrollSeconds ?? 180 },
            set: { newValue in
                song.autoscrollSeconds = newValue
                autoscroller.duration = TimeInterval(newValue)
            }
        )
    }

    private func forward() {
        if !autoscroller.page(forward: true), let next {
            onSelect(next)
        }
    }

    private func backward() {
        if !autoscroller.page(forward: false), let previous {
            onSelect(previous)
        }
    }
}
