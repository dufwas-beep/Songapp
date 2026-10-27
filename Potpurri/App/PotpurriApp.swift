import SwiftData
import SwiftUI

@main
struct PotpurriApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Song.self, Setlist.self, SongNote.self, Highlight.self, JumpMarker.self, ChordStamp.self, SoundClip.self, GigLog.self], isUndoEnabled: true)
    }
}
