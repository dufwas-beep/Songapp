import Observation
import SwiftUI

/// De fem färgkoderna. Ordningen är låst (lila alltid längst till höger, rosa näst längst);
/// namnen väljer man själv genom att hålla in kolumnrubriken.
@MainActor
@Observable
final class ColorCodes {
    static let count = 5
    static let colors: [Color] = [
        Color(red: 0.18, green: 0.62, blue: 0.36),
        Color(red: 0.95, green: 0.61, blue: 0.07),
        Color(red: 0.23, green: 0.51, blue: 0.96),
        Color(red: 0.98, green: 0.57, blue: 1.0),
        Color(red: 0.55, green: 0.36, blue: 0.96)
    ]

    var names: [String] {
        didSet { UserDefaults.standard.set(names, forKey: "colorCodeNames") }
    }

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: "colorCodeNames") ?? []
        names = saved.count == Self.count ? saved : ["Grön", "Orange", "Blå", "Rosa", "Lila"]
    }
}
