import SwiftUI

/// Liggande: biblioteket till vänster och låten till höger.
/// Stående: låten i helskärm och biblioteket som en meny man drar fram.
struct ContentView: View {
    @State private var selection: Song?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LibraryView(selection: $selection)
        } detail: {
            SongDetailView(song: selection)
        }
    }
}
