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
                HStack(alignment: .center, spacing: 12) {
                    SongStepButtons(previous: previous, next: next, onSelect: onSelect)
                    AutoscrollButton(autoscroller: autoscroller, seconds: secondsBinding(for: song))
                }
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

/// Förra och nästa låt, nere till höger bredvid autoscrollknappen. Nästa visar låtens namn.
private struct SongStepButtons: View {
    let previous: Song?
    let next: Song?
    let onSelect: (Song) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if let previous { onSelect(previous) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 52, height: 56)
            }
            .disabled(previous == nil)
            .accessibilityLabel(previous.map { "Förra låten: \($0.title)" } ?? "Ingen förra låt")

            Divider()
                .frame(height: 30)

            Button {
                if let next { onSelect(next) }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("NÄSTA")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                        Text(next?.title ?? "Slut på listan")
                            .font(.system(size: 16, weight: .medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 240, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 18, weight: .semibold))
                }
                .padding(.leading, 14)
                .padding(.trailing, 16)
                .frame(height: 56)
            }
            .disabled(next == nil)
            .accessibilityLabel(next.map { "Nästa låt: \($0.title)" } ?? "Ingen nästa låt")
        }
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}
