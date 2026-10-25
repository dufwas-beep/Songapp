import SwiftUI

/// Liggande: låtlistor/bibliotek till vänster och låten till höger.
/// Stående: låten i helskärm och sidospalten som en meny man drar fram.
struct ContentView: View {
    @State private var selection: Song?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
        } detail: {
            SongDetailView(song: selection)
        }
    }
}
