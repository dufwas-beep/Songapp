import SwiftData
import SwiftUI

/// Liggande: låtlistor/bibliotek till vänster och låten till höger.
/// Stående: låten i helskärm och sidospalten som en meny man drar fram.
struct ContentView: View {
    @Query private var songs: [Song]
    @State private var selection: Song?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var player = Player()

    private func song(_ id: UUID?) -> Song? {
        guard let id else { return nil }
        return songs.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
        } detail: {
            SongDetailView(
                song: selection,
                previous: song(player.previous(before: selection?.id)),
                next: song(player.next(after: selection?.id)),
                onSelect: { selection = $0 }
            )
            .overlay(alignment: .topLeading) {
                // När sidospalten är dold visas klockan i låtvyn i stället.
                if columnVisibility == .detailOnly {
                    ClockLabel()
                        .padding(.leading, 70)
                        .padding(.top, 6)
                }
            }
        }
        .environment(player)
        .onAppear {
            // Skärmen släcks aldrig medan Potpurri är öppen.
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }
}

/// Liten klocka (TT:MM) när sidospalten är dold.
private struct ClockLabel: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date, format: Date.FormatStyle(locale: Locale(identifier: "sv_SE")).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
        }
    }
}
