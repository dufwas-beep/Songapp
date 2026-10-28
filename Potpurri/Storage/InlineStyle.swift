import SwiftUI

/// Fet och kursiv text i textlåtar och anteckningar: **fet** och *kursiv*, som i
/// Markdown. Stjärnorna syns aldrig i låten – bara i redigeringen.
enum InlineStyle {
    /// Formaterad text. `bold`/`italic` följer med till nästa bit på samma rad, så att
    /// en markering kan gå över flera ord.
    static func attributed(_ text: String, size: CGFloat, weight: Font.Weight = .regular, bold: inout Bool, italic: inout Bool) -> AttributedString {
        var result = AttributedString()
        var run = ""
        func flush() {
            guard !run.isEmpty else { return }
            var piece = AttributedString(run)
            var font = Font.system(size: size, weight: bold ? .bold : weight)
            if italic { font = font.italic() }
            piece.font = font
            result += piece
            run = ""
        }
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            if characters[index] == "*" {
                flush()
                if index + 1 < characters.count && characters[index + 1] == "*" {
                    bold.toggle()
                    index += 2
                } else {
                    italic.toggle()
                    index += 1
                }
                continue
            }
            run.append(characters[index])
            index += 1
        }
        flush()
        return result
    }

    /// En hel rad (markeringen börjar om på varje rad).
    static func attributed(_ text: String, size: CGFloat, weight: Font.Weight = .regular) -> AttributedString {
        var bold = false
        var italic = false
        return attributed(text, size: size, weight: weight, bold: &bold, italic: &italic)
    }

    /// Texten utan stjärnor (t.ex. för rubriker).
    static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "*", with: "")
    }
}

/// Textruta för låttext med knappar för fet och kursiv text och "Klistra in".
/// Markera text och tryck B eller I – trycker man igen tas markeringen bort.
struct StyledTextEditor: View {
    @Binding var text: String
    @State private var selection: TextSelection?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    wrap("**")
                } label: {
                    Image(systemName: "bold")
                        .frame(width: 32, height: 28)
                }
                .accessibilityLabel("Fet")
                Button {
                    wrap("*")
                } label: {
                    Image(systemName: "italic")
                        .frame(width: 32, height: 28)
                }
                .accessibilityLabel("Kursiv")
                Spacer()
                PasteButton(payloadType: String.self) { strings in
                    guard let pasted = strings.first else { return }
                    Task { @MainActor in insert(pasted) }
                }
                .buttonBorderShape(.capsule)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            TextEditor(text: $text, selection: $selection)
                .font(.system(size: 19, design: .monospaced))
                .padding(.horizontal, 12)
        }
    }

    /// Det markerade (eller markören) i texten. Utan markering: slutet av texten.
    private var selectedRange: Range<String.Index> {
        if let selection, case .selection(let range) = selection.indices,
           range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex {
            return range
        }
        return text.endIndex..<text.endIndex
    }

    /// Lägger stjärnor runt det markerade – eller tar bort dem om de redan finns.
    private func wrap(_ marker: String) {
        let range = selectedRange
        let before = String(text[..<range.lowerBound])
        let selected = String(text[range])
        let after = String(text[range.upperBound...])
        let start = before.count
        let inner: String
        let newText: String
        if selected.count >= marker.count * 2 && selected.hasPrefix(marker) && selected.hasSuffix(marker) {
            inner = String(selected.dropFirst(marker.count).dropLast(marker.count))
            newText = before + inner + after
            select(in: newText, from: start, length: inner.count)
        } else {
            inner = selected
            newText = before + marker + inner + marker + after
            select(in: newText, from: start + marker.count, length: inner.count)
        }
    }

    /// Klistrar in där markören står (eller ersätter det markerade).
    private func insert(_ pasted: String) {
        let range = selectedRange
        let before = String(text[..<range.lowerBound])
        let after = String(text[range.upperBound...])
        select(in: before + pasted + after, from: before.count + pasted.count, length: 0)
    }

    private func select(in newText: String, from offset: Int, length: Int) {
        text = newText
        let lower = newText.index(newText.startIndex, offsetBy: min(offset, newText.count))
        let upper = newText.index(lower, offsetBy: min(length, newText.distance(from: lower, to: newText.endIndex)))
        selection = lower == upper ? TextSelection(insertionPoint: lower) : TextSelection(range: lower..<upper)
    }
}
