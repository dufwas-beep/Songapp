import SwiftUI
import UIKit

/// Alfabetet vid sidan av biblioteket. Dra fingret längs bokstäverna: de närmast fingret
/// förstoras (som Dock på en Mac), en stor bokstav visas bredvid och studsar till vid varje
/// byte, och listan hoppar dit. Bokstäver utan låtar är nedtonade. (iPad saknar
/// vibrationsmotor; på enheter som har en ger bytet också ett kort "tick".)
struct AlphabetScrubber: View {
    static let letters = (65...90).map { String(UnicodeScalar($0)!) } + ["Å", "Ä", "Ö", "#"]

    let available: Set<String>
    let onSelect: (String) -> Void

    @State private var touchY: CGFloat?
    @State private var current: String?
    @State private var pulse = false
    private let feedback = UISelectionFeedbackGenerator()

    var body: some View {
        GeometryReader { geometry in
            let step = geometry.size.height / CGFloat(Self.letters.count)
            VStack(spacing: 0) {
                ForEach(Array(Self.letters.enumerated()), id: \.offset) { index, letter in
                    let scale = magnification(at: step * (CGFloat(index) + 0.5))
                    Text(letter)
                        .font(.system(size: min(13, step * 0.7), weight: .semibold))
                        .foregroundStyle(available.contains(letter) ? Color.primary : Color.secondary.opacity(0.35))
                        .scaleEffect(scale, anchor: .trailing)
                        .offset(x: -(scale - 1) * 16)
                        .frame(width: 26, height: step)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let current, let touchY {
                    Text(current)
                        .font(.system(size: 46, weight: .bold))
                        .frame(width: 84, height: 84)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 3))
                        .scaleEffect(pulse ? 1.15 : 1)
                        .offset(x: -70, y: min(max(touchY - 42, 0), geometry.size.height - 84))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        touchY = value.location.y
                        let index = min(max(Int(value.location.y / step), 0), Self.letters.count - 1)
                        let letter = Self.letters[index]
                        guard letter != current else { return }
                        current = letter
                        feedback.selectionChanged()
                        withAnimation(.easeOut(duration: 0.08)) {
                            pulse = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                                pulse = false
                            }
                        }
                        // Saknas bokstaven hoppar listan till nästa bokstav som har låtar.
                        if let target = Self.letters[index...].first(where: available.contains) {
                            onSelect(target)
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            touchY = nil
                            current = nil
                        }
                    }
            )
            .animation(.interactiveSpring(response: 0.2), value: touchY)
        }
        .frame(width: 26)
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }

    /// Förstoring för en bokstav beroende på hur nära fingret den är.
    private func magnification(at y: CGFloat) -> CGFloat {
        guard let touchY else { return 1 }
        let distance = abs(y - touchY)
        return 1 + 1.1 * max(0, 1 - distance / 60)
    }
}

/// En rullist att dra i (Quiz-fliken): tummen visar var i listan man är, och drar man
/// längs den hoppar listan dit, med namnet på raden i en bubbla bredvid.
struct ScrollScrubber: View {
    let titles: [String]
    /// Var listan är scrollad, 0 = överst, 1 = nederst.
    let fraction: Double
    let onSelect: (Int) -> Void

    @State private var dragFraction: Double?
    @State private var current: Int?
    private let feedback = UISelectionFeedbackGenerator()
    private let thumbHeight: CGFloat = 44

    var body: some View {
        GeometryReader { geometry in
            let travel = max(geometry.size.height - thumbHeight, 1)
            let shown = min(max(dragFraction ?? fraction, 0), 1)
            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 6)
                    .frame(maxHeight: .infinity)
                Capsule()
                    .fill(dragFraction == nil ? Color.secondary.opacity(0.6) : Color.accentColor)
                    .frame(width: dragFraction == nil ? 8 : 12, height: thumbHeight)
                    .offset(y: travel * shown)
            }
            .frame(width: 26)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .overlay(alignment: .topTrailing) {
                if let current, titles.indices.contains(current) {
                    Text(titles[current])
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.accentColor, lineWidth: 2))
                        .fixedSize()
                        .offset(x: -36, y: travel * shown + thumbHeight / 2 - 18)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !titles.isEmpty else { return }
                        let f = min(max(Double((value.location.y - thumbHeight / 2) / travel), 0), 1)
                        dragFraction = f
                        let index = min(Int((f * Double(titles.count - 1)).rounded()), titles.count - 1)
                        guard index != current else { return }
                        current = index
                        feedback.selectionChanged()
                        onSelect(index)
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            dragFraction = nil
                            current = nil
                        }
                    }
            )
        }
        .frame(width: 26)
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }
}
