import Observation
import SwiftUI

/// Ställen på skärmen som guiden kan peka på.
enum GuideSpot: String {
    case logo, tabs, addSong, categories, next, newGig, pause
    case songMenu, soundboard, spotify, stepButtons, settings, sidebarToggle, drawer
}

/// Var på skärmen guidens ställen finns just nu (i fönstrets koordinater).
/// Fylls i av vyerna själva med `.guideSpot(_:)`; läses bara av guiden.
@MainActor
@Observable
final class GuideSpots {
    static let shared = GuideSpots()
    private var frames: [GuideSpot: (owner: UUID, frame: CGRect)] = [:]

    func frame(_ spot: GuideSpot) -> CGRect? {
        frames[spot]?.frame
    }

    fileprivate func set(_ spot: GuideSpot, owner: UUID, frame: CGRect) {
        frames[spot] = (owner, frame)
    }

    fileprivate func remove(_ spot: GuideSpot, owner: UUID) {
        if frames[spot]?.owner == owner { frames[spot] = nil }
    }
}

private struct GuideSpotModifier: ViewModifier {
    let spot: GuideSpot
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                GuideSpots.shared.set(spot, owner: owner, frame: frame)
            }
            .onDisappear { GuideSpots.shared.remove(spot, owner: owner) }
    }
}

extension View {
    /// Talar om för guiden var den här delen av skärmen finns.
    func guideSpot(_ spot: GuideSpot) -> some View {
        modifier(GuideSpotModifier(spot: spot))
    }
}

/// En sida i guiden: vad den visar och var på skärmen (om någonstans).
struct GuidePage {
    let symbol: String
    let title: String
    let text: String
    var spot: GuideSpot?
    /// Fliken i sidospalten som ska visas på sidan (t.ex. Bibliotek för +).
    var tab: SidebarView.SidebarTab?
}

/// Rundturen ovanpå appen: allt tonas ner utom stället guiden pratar om, som ramas in
/// i rosa. Rutan med texten hamnar bredvid. Finns stället inte på skärmen just nu
/// (t.ex. ingen låt vald) visas rutan i mitten.
struct GuideTour: View {
    let pages: [GuidePage]
    let onClose: () -> Void
    @State private var index = 0
    @AppStorage("sidebarTab") private var tab = SidebarView.SidebarTab.setlists
    private static let cardSize = CGSize(width: 360, height: 250)

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let page = pages[min(index, pages.count - 1)]
            let hole = spotRect(for: page, origin: origin, size: proxy.size)
            ZStack {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: proxy.size))
                    if let hole { path.addRoundedRect(in: hole, cornerSize: CGSize(width: 16, height: 16)) }
                }
                .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
                if let hole {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.accentColor, lineWidth: 4)
                        .frame(width: hole.width, height: hole.height)
                        .phaseAnimator([1.0, 1.04]) { content, scale in
                            content.scaleEffect(scale)
                        } animation: { _ in
                            .easeInOut(duration: 0.7)
                        }
                        .position(x: hole.midX, y: hole.midY)
                        .allowsHitTesting(false)
                }
                card(page, pointsAtSpot: hole != nil)
                    .position(cardCenter(hole: hole, in: proxy.size))
            }
            .animation(.easeInOut(duration: 0.3), value: index)
        }
        .ignoresSafeArea()
        // Appen under går inte att trycka på medan guiden visas.
        .contentShape(Rectangle())
        .onTapGesture {}
        .onAppear { showTab() }
        .onChange(of: index) { showTab() }
    }

    private func showTab() {
        if let wanted = pages[min(index, pages.count - 1)].tab { tab = wanted }
    }

    private func spotRect(for page: GuidePage, origin: CGPoint, size: CGSize) -> CGRect? {
        guard let spot = page.spot, let frame = GuideSpots.shared.frame(spot) else { return nil }
        let rect = frame.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -10, dy: -10)
        // Utanför skärmen (t.ex. en dold sidospalt) räknas som att det inte syns.
        guard rect.width > 20, rect.height > 20, CGRect(origin: .zero, size: size).intersects(rect) else { return nil }
        return rect
    }

    private func card(_ page: GuidePage, pointsAtSpot: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if page.symbol == "logo" {
                    Image("LPLogo").resizable().frame(width: 34, height: 34)
                } else {
                    Image(systemName: page.symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 34)
                }
                Text(page.title)
                    .font(.title3.bold())
            }
            Text(page.text)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if page.spot != nil && !pointsAtSpot {
                Text("Den här delen syns när en låt är vald och listorna visas.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 10) {
                Button("Hoppa över", action: onClose)
                    .font(.footnote)
                Spacer()
                Text("\(index + 1) av \(pages.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if index > 0 {
                    Button {
                        index -= 1
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Tillbaka")
                }
                Button(index < pages.count - 1 ? "Nästa" : "Kör igång!") {
                    if index < pages.count - 1 { index += 1 } else { onClose() }
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.black)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(width: Self.cardSize.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
    }

    /// Rutan bredvid stället: helst till höger, annars till vänster, under eller över.
    private func cardCenter(hole: CGRect?, in size: CGSize) -> CGPoint {
        let card = Self.cardSize
        let margin: CGFloat = 16
        let gap: CGFloat = 18
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, margin + card.width / 2), size.width - margin - card.width / 2) }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, margin + card.height / 2), size.height - margin - card.height / 2) }
        guard let hole else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        if hole.maxX + gap + card.width + margin < size.width {
            return CGPoint(x: hole.maxX + gap + card.width / 2, y: clampY(hole.midY))
        }
        if hole.minX - gap - card.width - margin > 0 {
            return CGPoint(x: hole.minX - gap - card.width / 2, y: clampY(hole.midY))
        }
        if hole.maxY + gap + card.height + margin < size.height {
            return CGPoint(x: clampX(hole.midX), y: hole.maxY + gap + card.height / 2)
        }
        return CGPoint(x: clampX(hole.midX), y: clampY(hole.minY - gap - card.height / 2))
    }
}
