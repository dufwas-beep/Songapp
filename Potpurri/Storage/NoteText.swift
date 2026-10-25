import Foundation

/// Gör quizmanus (vanlig text) lättare att läsa på scen genom att känna igen mönstren:
/// "1 VÄLKOMMEN OMBORD" blir rubrik, "C  Mausoleum" blir svar och "LÅT Benjamin" tonas ner.
enum NoteText {
    enum Style {
        case heading
        case question
        case answer
        case muted
        case normal
        case blank
    }

    struct Line: Hashable {
        let style: Style
        let text: String
    }

    static func parse(_ text: String) -> [Line] {
        var result: [Line] = []
        for raw in text.components(separatedBy: .newlines) {
            // Tabbar från Word blir mellanslag; indraget i början tas bort.
            let line = raw.replacingOccurrences(of: "\t", with: "  ")
                .replacingOccurrences(of: "\\s{3,}", with: "   ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if let last = result.last, last.style != .blank { result.append(Line(style: .blank, text: "")) }
                continue
            }
            result.append(Line(style: style(of: line), text: displayText(line)))
        }
        while result.last?.style == .blank { result.removeLast() }
        return result
    }

    private static func style(of line: String) -> Style {
        // Svar: "C" följt av mellanslag, t.ex. "C  Mausoleum".
        if line.range(of: "^C\\s+\\S", options: .regularExpression) != nil { return .answer }
        // Fråga: "A)", "B)" eller "A:".
        if line.range(of: "^[A-Z][):]\\s", options: .regularExpression) != nil { return .question }
        // "LÅT Benjamin", "LÅT: …"
        if line.range(of: "^LÅT\\b", options: .regularExpression) != nil { return .muted }
        // Rubrik: börjar med ett nummer och består mest av versaler, t.ex. "1  VÄLKOMMEN OMBORD A & B".
        let letters = line.filter(\.isLetter)
        let upper = letters.filter(\.isUppercase)
        if !letters.isEmpty, Double(upper.count) / Double(letters.count) > 0.8 {
            if line.first?.isNumber == true || letters.count <= 40 { return .heading }
        }
        return .normal
    }

    /// Svarets "C" behövs inte när svaret redan är markerat.
    private static func displayText(_ line: String) -> String {
        if style(of: line) == .answer {
            return line.replacingOccurrences(of: "^C\\s+", with: "", options: .regularExpression)
        }
        return line
    }
}
