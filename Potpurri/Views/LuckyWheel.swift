import AudioToolbox
import SwiftData
import SwiftUI
import UIKit

/// Välkomstsidans lyckohjul. Dra runt hjulet och släpp (eller tryck) så snurrar det och
/// saktar in. Varje fält som passerar pilen ger ett klick och flyttar markeringen en låt
/// i biblioteket; där hjulet stannar öppnas låten.
struct LuckyWheel: View {
    var size: CGFloat = 220
    @Environment(Player.self) private var player
    @AppStorage("sidebarTab") private var sidebarTab = SidebarView.SidebarTab.setlists
    @Query private var songs: [Song]

    @State private var angle: Double = 0
    @State private var velocity: Double = 0
    @State private var spinning = false
    @State private var lastDragAngle: Double?
    @State private var lastDragTime: Date?
    @State private var dragVelocity: Double = 0
    /// Pilen knycker till vid varje klick.
    @State private var flick = false
    @State private var lastClick = Date.distantPast

    private static let segments = 16
    private static var segmentAngle: Double { 360 / Double(segments) }
    private static let colors: [Color] = ColorCodes.colors

    var body: some View {
        ZStack(alignment: .top) {
            wheel
                .rotationEffect(.degrees(angle))
                .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
            // Pilen överst, som hjulet klickar mot.
            Pointer()
                .fill(Color.primary)
                .frame(width: 26, height: 30)
                .rotationEffect(.degrees(flick ? -22 : 0), anchor: .top)
                .offset(y: -12)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(dragGesture)
        .onTapGesture {
            guard !spinning else { return }
            spin(velocity: Double.random(in: 900...1500))
        }
        .accessibilityLabel("Lyckohjulet – snurra för att slumpa fram en låt")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            spin(velocity: Double.random(in: 900...1500))
        }
    }

    private var wheel: some View {
        Canvas { context, canvasSize in
            let radius = min(canvasSize.width, canvasSize.height) / 2
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            for index in 0..<Self.segments {
                // Fält 0 börjar vid pilen (överst).
                let start = Angle.degrees(Double(index) * Self.segmentAngle - 90)
                let end = Angle.degrees(Double(index + 1) * Self.segmentAngle - 90)
                var path = Path()
                path.move(to: center)
                path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
                path.closeSubpath()
                context.fill(path, with: .color(Self.colors[index % Self.colors.count]))
                context.stroke(path, with: .color(.white.opacity(0.85)), lineWidth: 2)
            }
            // Pinnarna i kanten som pilen klickar mot.
            for index in 0..<Self.segments {
                let a = (Double(index) * Self.segmentAngle - 90) * .pi / 180
                let point = CGPoint(x: center.x + cos(a) * (radius - 7), y: center.y + sin(a) * (radius - 7))
                context.fill(Path(ellipseIn: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)), with: .color(.white))
            }
            context.stroke(Path(ellipseIn: CGRect(x: 1, y: 1, width: canvasSize.width - 2, height: canvasSize.height - 2)), with: .color(.black.opacity(0.25)), lineWidth: 2)
        }
        .overlay {
            // Potpurri-skivan i mitten.
            VectorRecord()
                .frame(width: size * 0.36, height: size * 0.36)
        }
    }

    // MARK: Dra och snurra

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !spinning else { return }
                let center = CGPoint(x: size / 2, y: size / 2)
                let current = atan2(Double(value.location.y - center.y), Double(value.location.x - center.x)) * 180 / .pi
                let now = Date()
                if let last = lastDragAngle, let lastTime = lastDragTime {
                    var delta = current - last
                    if delta > 180 { delta -= 360 }
                    if delta < -180 { delta += 360 }
                    rotate(by: delta)
                    let seconds = max(now.timeIntervalSince(lastTime), 0.008)
                    // Utjämnad fart, så att ett ryck i sista stund inte avgör allt.
                    dragVelocity = dragVelocity * 0.5 + (delta / seconds) * 0.5
                }
                lastDragAngle = current
                lastDragTime = now
            }
            .onEnded { _ in
                defer {
                    lastDragAngle = nil
                    lastDragTime = nil
                    dragVelocity = 0
                }
                guard !spinning else { return }
                // Ett lugnt drag ger ändå ett ordentligt snurr åt samma håll.
                let direction: Double = dragVelocity < 0 ? -1 : 1
                let speed = min(max(abs(dragVelocity), 700), 2600)
                spin(velocity: direction * speed)
            }
    }

    private func spin(velocity start: Double) {
        guard !spinning else { return }
        spinning = true
        velocity = start
        sidebarTab = .library
        player.wheelSpinning = true
        Task { @MainActor in
            var last = Date()
            // Saktar in mjukt (friktion) och sist lite fastare, så att hjulet stannar
            // på ungefär sex–åtta sekunder.
            while abs(velocity) > 6 {
                try? await Task.sleep(for: .milliseconds(16))
                let now = Date()
                let dt = min(now.timeIntervalSince(last), 0.05)
                last = now
                rotate(by: velocity * dt)
                let slowed = abs(velocity) * exp(-0.55 * dt) - 22 * dt
                velocity = velocity < 0 ? -max(slowed, 0) : max(slowed, 0)
            }
            velocity = 0
            spinning = false
            player.wheelSpinning = false
            // Syns inte biblioteket (spalten är dold) blir det en slumpad låt ändå.
            if player.wheelSongID == nil, let song = songs.filter({ !LibraryView.isQuiz($0) }).randomElement() {
                player.requestedSongID = song.id
            }
        }
    }

    /// Vrider hjulet; varje fält som passerar pilen klickar och flyttar en låt.
    private func rotate(by delta: Double) {
        let before = Int(floor(angle / Self.segmentAngle))
        angle += delta
        let after = Int(floor(angle / Self.segmentAngle))
        let passed = abs(after - before)
        guard passed > 0 else { return }
        player.wheelTicks += passed
        click()
    }

    private func click() {
        let now = Date()
        // Högst ett klickljud var 35:e millisekund – fortare låter det bara som ett surr.
        guard now.timeIntervalSince(lastClick) > 0.035 else { return }
        lastClick = now
        AudioServicesPlaySystemSound(1104)
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeOut(duration: 0.04)) { flick = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.45)) { flick = false }
        }
    }
}

/// Pilen: en nedåtriktad triangel med rundad topp.
private struct Pointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
