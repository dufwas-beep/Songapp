import Observation
import SwiftUI

/// Kategorierna (färgkoderna). Upp till sju, fem rekommenderas. Ordningen är låst
/// (lila alltid längst till höger av de fem första); namnen väljer man själv genom att
/// hålla in kolumnrubriken eller under "Kategorier" i kategoriläget.
@MainActor
@Observable
final class ColorCodes {
    nonisolated static let maxCount = 7
    nonisolated static let recommendedCount = 5
    static let colors: [Color] = [
        Color(red: 0.18, green: 0.62, blue: 0.36),
        Color(red: 0.95, green: 0.61, blue: 0.07),
        Color(red: 0.23, green: 0.51, blue: 0.96),
        Color(red: 0.98, green: 0.57, blue: 1.0),
        Color(red: 0.55, green: 0.36, blue: 0.96),
        Color(red: 0.91, green: 0.25, blue: 0.24),
        Color(red: 0.10, green: 0.74, blue: 0.78)
    ]
    nonisolated static let defaultNames = ["Grön", "Orange", "Blå", "Rosa", "Lila", "Röd", "Turkos"]

    /// Namnen på alla sju (även de som inte används just nu).
    var names: [String] {
        didSet { UserDefaults.standard.set(names, forKey: "colorCodeNames") }
    }

    /// Hur många kategorier som används (1–7).
    var count: Int {
        didSet { UserDefaults.standard.set(count, forKey: "categoryCount") }
    }

    init() {
        names = Self.filled(UserDefaults.standard.stringArray(forKey: "colorCodeNames") ?? [])
        let saved = UserDefaults.standard.integer(forKey: "categoryCount")
        count = saved > 0 ? min(saved, Self.maxCount) : Self.recommendedCount
    }

    /// Fyller ut sparade namn (t.ex. bara fem från en äldre version) till sju.
    nonisolated static func filled(_ saved: [String]) -> [String] {
        (0..<maxCount).map { index in
            index < saved.count && !saved[index].isEmpty ? saved[index] : defaultNames[index]
        }
    }
}
