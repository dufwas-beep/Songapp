import SwiftUI

/// Svep på en rad: åt vänster visas Ta bort (svep hela vägen = ta bort direkt),
/// åt höger visas knapparna i `leading` (svep hela vägen = `onFullSwipeRight`, t.ex. Lådan).
struct SwipeRow<Leading: View>: ViewModifier {
    let canDelete: Bool
    let onDelete: () -> Void
    var onFullSwipeRight: (() -> Void)? = nil
    @ViewBuilder let leading: (_ close: @escaping () -> Void) -> Leading
    @State private var offset: CGFloat = 0
    @State private var start: CGFloat?
    @State private var horizontal: Bool?
    /// Raden flyger iväg åt höger (mot Lådan) och tonar sedan tillbaka.
    @State private var flying = false

    private static var leadingWidth: CGFloat { SwipeButtonLabel.width }
    private static var deleteWidth: CGFloat { SwipeButtonLabel.width }

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .opacity(flying ? 0 : 1)
            // När raden är uppsvept stänger ett tryck den i stället för att öppna låten.
            .overlay {
                if offset != 0 {
                    Color.clear
                        .contentShape(Rectangle())
                        .offset(x: offset)
                        .onTapGesture { close() }
                }
            }
            .background(alignment: .leading) {
                HStack(spacing: 0) { leading(close) }
                    .frame(width: max(offset, 0), alignment: .leading)
                    .clipped()
            }
            .background(alignment: .trailing) {
                SwipeButton(title: "Ta bort", systemImage: "trash", color: .red) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { offset = 0 }
                    onDelete()
                }
                .frame(width: max(-offset, 0), alignment: .trailing)
                .clipped()
            }
            .clipped()
            .simultaneousGesture(
                DragGesture(minimumDistance: 16)
                    .onChanged { value in
                        if horizontal == nil {
                            horizontal = abs(value.translation.width) > abs(value.translation.height)
                        }
                        guard horizontal == true else { return }
                        let begin = start ?? offset
                        start = begin
                        let maxLeft: CGFloat = canDelete ? -320 : 0
                        let maxRight: CGFloat = onFullSwipeRight == nil ? Self.leadingWidth + 40 : 400
                        offset = min(max(begin + value.translation.width, maxLeft), maxRight)
                    }
                    .onEnded { _ in
                        defer {
                            start = nil
                            horizontal = nil
                        }
                        guard horizontal == true else { return }
                        if let onFullSwipeRight, offset > 200 {
                            flyAway(onFullSwipeRight)
                            return
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                            if offset < -220 {
                                offset = 0
                                onDelete()
                            } else if offset < -40 {
                                offset = -Self.deleteWidth
                            } else if offset > 50 {
                                offset = Self.leadingWidth
                            } else {
                                offset = 0
                            }
                        }
                    }
            )
    }

    /// Raden glider ut åt höger och tonar bort, Lådan öppnas, och raden tonar tillbaka.
    private func flyAway(_ action: @escaping () -> Void) {
        withAnimation(.easeIn(duration: 0.22)) {
            offset = 700
            flying = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            action()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { offset = 0 }
            withAnimation(.easeOut(duration: 0.35).delay(0.15)) { flying = false }
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { offset = 0 }
    }
}

struct SwipeButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SwipeButtonLabel(title: title, systemImage: systemImage, color: color)
        }
        .buttonStyle(.plain)
    }
}

struct SwipeButtonLabel: View {
    static let width: CGFloat = 86
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(color)
    }
}
