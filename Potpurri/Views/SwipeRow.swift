import SwiftUI

/// Svep på en rad: åt vänster visas Ta bort (svep hela vägen = ta bort direkt),
/// åt höger visas knapparna i `leading`.
struct SwipeRow<Leading: View>: ViewModifier {
    let canDelete: Bool
    let onDelete: () -> Void
    @ViewBuilder let leading: (_ close: @escaping () -> Void) -> Leading
    @State private var offset: CGFloat = 0
    @State private var start: CGFloat?
    @State private var horizontal: Bool?

    private static var leadingWidth: CGFloat { SwipeButtonLabel.width }
    private static var deleteWidth: CGFloat { SwipeButtonLabel.width }

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
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
                        offset = min(max(begin + value.translation.width, maxLeft), Self.leadingWidth + 40)
                    }
                    .onEnded { _ in
                        defer {
                            start = nil
                            horizontal = nil
                        }
                        guard horizontal == true else { return }
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
