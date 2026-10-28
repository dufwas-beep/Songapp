import Foundation
import SwiftData

/// En rad i Idélådan: ett låtförslag, något att köpa, något att testa … Sorteras
/// automatiskt i en kategori när den skrivs (går att ändra).
@Model
final class Idea {
    var id: UUID = UUID()
    var text: String = ""
    var categoryRaw: String = IdeaCategory.remember.rawValue
    var created: Date = Date()
    var done: Bool = false

    init(text: String, category: IdeaCategory) {
        self.id = UUID()
        self.text = text
        self.categoryRaw = category.rawValue
        self.created = Date()
    }

    var category: IdeaCategory {
        get { IdeaCategory(rawValue: categoryRaw) ?? .remember }
        set { categoryRaw = newValue.rawValue }
    }
}

enum IdeaCategory: String, CaseIterable, Identifiable {
    case buy, rehearse, test, remember, app
    var id: Self { self }

    var title: String {
        switch self {
        case .buy: "Att köpa"
        case .rehearse: "Att repa in"
        case .test: "Att testa"
        case .remember: "Att komma ihåg"
        case .app: "Appen"
        }
    }

    var symbol: String {
        switch self {
        case .buy: "cart"
        case .rehearse: "music.mic"
        case .test: "flask"
        case .remember: "pin"
        case .app: "hammer"
        }
    }

    /// Gissar kategorin utifrån orden i texten. Utan träff: Att komma ihåg.
    static func guess(for text: String) -> IdeaCategory {
        let words = text.lowercased()
        let rules: [(IdeaCategory, [String])] = [
            (.app, ["appen", "potpurri", "knapp", "funktion", "bugg", "krasch", "guiden", "inställning", "skärmen", "förbättr"]),
            (.buy, ["köp", "beställ", "inhandla", "handla", "kabel", "kablar", "sladd", "batteri", "strängar", "stativ", "adapter", "laddare", "mikrofon", "hörlurar", "kr ", "kronor", "pris"]),
            (.rehearse, ["repa", "öva", "lära", "lär in", "låtförslag", "önskelåt", "önskad", "önskemål", "spela ", "ny låt", "tips på låt", "cover"]),
            (.test, ["testa", "prova", "försök", "experiment", "kolla om", "pröva"]),
        ]
        for (category, keys) in rules where keys.contains(where: { words.contains($0) }) {
            return category
        }
        return .remember
    }
}
