import SwiftUI

/// Redigera en textlåt (eller anteckning). Ackord kan skrivas i hakparenteser
/// ("Jag [G]går") eller på en egen rad ovanför texten.
struct SongTextEditor: View {
    @Bindable var song: Song
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $draft)
                .font(.system(size: 19, design: .monospaced))
                .padding(.horizontal, 12)
                .navigationTitle(song.title)
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .top) {
                    Text(song.kind == .note
                         ? "Skriv anteckningen. Frågor (A), B)) och svar (C …) formateras automatiskt."
                         : "Ackord skrivs i hakparenteser, t.ex. Jag [G]går hem – eller på en egen rad ovanför texten. Rader som \"Vers 1:\" blir rubriker.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.bar)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Avbryt") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Spara") {
                            song.text = draft
                            dismiss()
                        }
                    }
                }
                .onAppear { draft = song.text ?? "" }
        }
    }
}
