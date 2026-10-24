import SwiftData
import SwiftUI

@main
struct PotpurriApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Song.self)
    }
}
