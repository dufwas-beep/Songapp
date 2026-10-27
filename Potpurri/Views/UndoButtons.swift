import SwiftUI

/// Ångra och Gör om – visas i verktyget man håller på med (penna, ackord, hopplinjer, note).
struct UndoButtons: View {
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        HStack(spacing: 4) {
            Button {
                undoManager?.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel("Ångra")
            Button {
                undoManager?.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel("Gör om")
        }
        .font(.system(size: 17, weight: .semibold))
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
    }
}
