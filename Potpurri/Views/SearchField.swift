import SwiftUI

/// Sökruta i sidospalten.
struct SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Rensa sökningen")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
    }
}
