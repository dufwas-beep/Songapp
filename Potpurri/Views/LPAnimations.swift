import SwiftUI

/// Start: skivan snurrar i mitten (ca 1 s) och glider sedan upp till sin plats i sidospalten.
struct LaunchAnimation: View {
    @State private var phase = 0
    @State private var angle: Double = 0

    var body: some View {
        if phase < 2 {
            GeometryReader { proxy in
                ZStack {
                    Color(.systemBackground)
                        .opacity(phase == 0 ? 1 : 0)
                    Image("LPLogo")
                        .resizable()
                        .frame(width: phase == 0 ? 260 : 46, height: phase == 0 ? 260 : 46)
                        .rotationEffect(.degrees(angle))
                        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                        .position(phase == 0 ? CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2) : CGPoint(x: 39, y: 52))
                        .opacity(phase == 0 ? 1 : 0.6)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .task {
                withAnimation(.linear(duration: 1.1)) { angle = 540 }
                try? await Task.sleep(for: .seconds(1.0))
                withAnimation(.spring(response: 0.7, dampingFraction: 0.9)) { phase = 1 }
                try? await Task.sleep(for: .seconds(0.75))
                phase = 2
            }
            .accessibilityHidden(true)
        }
    }
}

/// Påskägget: dubbeltryck på LP:n – duvan lyfter från etiketten, flaxar i skurar och glider
/// i en båge över skärmen, lutar i svängarna och glider tillbaka in i LP:n. Ca 3,5 s.
struct DoveFlight: View {
    let start: Date
    static let duration: Double = 3.5

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { context in
                let t = min(1, context.date.timeIntervalSince(start) / Self.duration)
                let state = flightState(t, size: proxy.size)
                Image("DoveFlap\(state.frame)")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220)
                    .scaleEffect(x: state.facingRight ? state.scale : -state.scale, y: state.scale)
                    .rotationEffect(.degrees(state.tilt))
                    .position(state.position)
                    .opacity(t < 0.04 ? t / 0.04 : (t > 0.94 ? (1 - t) / 0.06 : 1))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private struct State {
        var position: CGPoint
        var scale: CGFloat
        var tilt: Double
        var frame: Int
        var facingRight: Bool
    }

    /// Bana: ut från LP:n uppe till vänster, en stor båge över skärmen och tillbaka.
    private func flightState(_ t: Double, size: CGSize) -> State {
        let home = CGPoint(x: 39, y: 52)
        let angle = t * 2 * .pi
        let x = home.x + (size.width * 0.42) * (1 - cos(angle)) + size.width * 0.05 * sin(angle * 2)
        let y = home.y + size.height * 0.32 * sin(angle) + size.height * 0.18 * (1 - cos(angle))
        // Riktning (derivatan) för att vända och luta duvan.
        let dx = sin(angle) + 0.24 * cos(angle * 2)
        let dy = cos(angle) + 0.56 * sin(angle)
        let tilt = max(-25, min(25, atan2(dy, abs(dx)) * 180 / .pi * 0.5))
        // Växer ut ur etiketten och krymper tillbaka in i den.
        let scale = CGFloat(0.12 + 0.88 * sin(.pi * t))
        // Flaxar i skurar och glider emellan; bromsar med vingarna uppåt i slutet.
        let flapping = (t * 5).truncatingRemainder(dividingBy: 1) < 0.55
        let frames = [0, 1, 2, 3, 4, 3, 2, 1]
        let frame: Int
        if t > 0.86 {
            frame = 4
        } else if flapping {
            frame = frames[Int(t * 90) % frames.count]
        } else {
            frame = 2
        }
        return State(position: CGPoint(x: x, y: y), scale: scale, tilt: dx >= 0 ? tilt : -tilt, frame: frame, facingRight: dx >= 0)
    }
}

/// Importen: en pickup-arm som långsamt rör sig in över skivan, från kanten mot mitten,
/// i takt med hur långt importen har kommit.
struct ImportArm: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Image("LPLogo")
                .resizable()
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(fraction * 360 * 6))
            Capsule()
                .fill(Color.secondary)
                .frame(width: 3, height: 30)
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.primary).frame(width: 6, height: 7)
                }
                .offset(y: -12)
                .rotationEffect(.degrees(-50 + 38 * fraction), anchor: .top)
                .offset(x: 22, y: -8)
        }
        .frame(width: 56, height: 46)
        .animation(.easeInOut(duration: 0.4), value: fraction)
        .accessibilityHidden(true)
    }
}
