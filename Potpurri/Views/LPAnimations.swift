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
                    VectorRecord()
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

/// Påskägget: dubbeltryck på LP:n – en duva lyfter från etiketten, flyger en mjuk slinga
/// över skärmen (alltid innanför kanterna), glider en stund, lutar i svängarna och landar
/// tillbaka i LP:n. Duvan ritas som vektorgrafik med vingar som slår mjukt. Ca 4 s.
struct DoveFlight: View {
    let start: Date
    static let duration: Double = 4.2

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(start)
                let t = min(1, max(0, elapsed / Self.duration))
                let state = DoveFlightPath.state(t, elapsed: elapsed, size: size)
                context.opacity = t < 0.03 ? t / 0.03 : (t > 0.95 ? (1 - t) / 0.05 : 1)
                context.translateBy(x: state.position.x, y: state.position.y)
                context.rotate(by: .degrees(state.tilt))
                context.scaleBy(x: state.facing * state.scale, y: state.scale)
                DoveDrawing.draw(in: context, wing: state.wing)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Var duvan är, hur den lutar och hur vingarna står vid tiden t (0–1).
enum DoveFlightPath {
    struct State {
        var position: CGPoint
        var scale: CGFloat
        var tilt: Double
        /// −1 = vänd åt vänster, 1 = åt höger (däremellan medan den vänder).
        var facing: CGFloat
        /// Vingen: 1 = rakt upp, 0 = utsträckt (syns från kanten), −1 = rakt ner.
        var wing: CGFloat
    }

    static let home = CGPoint(x: 39, y: 52)
    /// Full storlek: duvan är ca 210 punkter lång, visas lite mindre.
    static let fullScale: CGFloat = 0.85

    /// Slingan, i andelar av skärmen. Börjar och slutar i LP:n uppe till vänster.
    private static let waypoints: [CGPoint] = [
        CGPoint(x: 0.30, y: 0.30), CGPoint(x: 0.60, y: 0.20), CGPoint(x: 0.80, y: 0.42),
        CGPoint(x: 0.62, y: 0.70), CGPoint(x: 0.34, y: 0.62), CGPoint(x: 0.20, y: 0.36)
    ]

    static func state(_ t: Double, elapsed: Double, size: CGSize) -> State {
        // Marginal så att hela duvan (vingarna inräknade) alltid syns.
        let margin: CGFloat = 120
        let points = [home] + waypoints.map { point in
            CGPoint(
                x: min(max(point.x * size.width, margin), max(margin, size.width - margin)),
                y: min(max(point.y * size.height, margin), max(margin, size.height - margin))
            )
        } + [home]
        // Långsamt i början och slutet (lyfter och landar), jämnt däremellan.
        let p = 0.5 - 0.5 * cos(.pi * t)
        let position = curve(points, p)
        let ahead = curve(points, min(1, p + 0.004))
        let behind = curve(points, max(0, p - 0.004))
        let dx = Double(ahead.x - behind.x)
        let dy = Double(ahead.y - behind.y)
        let speed = max(hypot(dx, dy), 0.0001)
        // Vänder genom att vingarna "vrids" – aldrig ett hopp från höger till vänster.
        let turn = max(-1, min(1, dx / (speed * 0.35)))
        let facing = CGFloat(turn >= 0 ? max(0.22, turn) : min(-0.22, turn))
        let pitch = max(-28, min(28, atan2(dy, abs(dx)) * 180 / .pi * 0.6))

        // Växer ur etiketten och krymper tillbaka in i den.
        let grow = min(1, t / 0.14)
        let shrink = min(1, (1 - t) / 0.14)
        let scale = fullScale * CGFloat(0.12 + 0.88 * min(grow, shrink))

        // Vingarna: snabba slag vid start och landning, glid två gånger på vägen,
        // och vingarna upp (bromsar) precis innan landningen.
        let flap = sin(elapsed * 2 * .pi * (t < 0.15 ? 6.5 : 5))
        let glide = max(window(t, 0.36, 0.50), window(t, 0.64, 0.74))
        var wing = CGFloat(flap * (1 - glide) + 0.42 * glide)
        if t > 0.9 { wing = CGFloat(0.85 + 0.1 * flap) }
        return State(position: position, scale: scale, tilt: turn >= 0 ? pitch : -pitch, facing: facing, wing: wing)
    }

    /// 0 utanför, 1 i mitten, mjuka kanter.
    private static func window(_ t: Double, _ from: Double, _ to: Double) -> Double {
        let edge = 0.03
        if t <= from || t >= to { return 0 }
        return min(1, (t - from) / edge, (to - t) / edge)
    }

    /// Mjuk kurva (Catmull–Rom) genom punkterna, p från 0 till 1.
    private static func curve(_ points: [CGPoint], _ p: Double) -> CGPoint {
        let segments = points.count - 1
        let x = min(max(p, 0), 1) * Double(segments)
        let index = min(Int(x), segments - 1)
        let u = CGFloat(x - Double(index))
        let p0 = points[max(index - 1, 0)]
        let p1 = points[index]
        let p2 = points[index + 1]
        let p3 = points[min(index + 2, points.count - 1)]
        func blend(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
            let u2 = u * u
            let u3 = u2 * u
            return 0.5 * ((2 * b) + (-a + c) * u + (2 * a - 5 * b + 4 * c - d) * u2 + (-a + 3 * b - 3 * c + d) * u3)
        }
        return CGPoint(x: blend(p0.x, p1.x, p2.x, p3.x), y: blend(p0.y, p1.y, p2.y, p3.y))
    }
}

/// Duvan, ritad med näbben åt höger och kroppens mitt i (0, 0). Ca 210 punkter lång.
/// Den bortre vingen ritas bakom kroppen, den närmre framför.
enum DoveDrawing {
    private static let shoulder = CGPoint(x: 8, y: -16)

    static func draw(in context: GraphicsContext, wing: CGFloat) {
        // Bortre vingen: lite efter i takten, mörkare och mindre.
        drawWing(in: context, lift: wing * 0.92 + 0.06, offset: CGPoint(x: 8, y: -4), size: 0.9, dark: true)
        drawTail(in: context)
        drawBody(in: context)
        drawWing(in: context, lift: wing, offset: .zero, size: 1, dark: false)
    }

    private static func drawTail(in context: GraphicsContext) {
        var tail = Path()
        tail.move(to: CGPoint(x: -38, y: -6))
        tail.addLine(to: CGPoint(x: -100, y: -17))
        tail.addQuadCurve(to: CGPoint(x: -102, y: 12), control: CGPoint(x: -110, y: -3))
        tail.addLine(to: CGPoint(x: -38, y: 12))
        tail.closeSubpath()
        context.fill(tail, with: .color(Color(red: 0.42, green: 0.45, blue: 0.52)))
        var band = Path()
        band.move(to: CGPoint(x: -88, y: -15))
        band.addLine(to: CGPoint(x: -100, y: -17))
        band.addQuadCurve(to: CGPoint(x: -102, y: 12), control: CGPoint(x: -110, y: -3))
        band.addLine(to: CGPoint(x: -90, y: 12))
        band.closeSubpath()
        context.fill(band, with: .color(Color(red: 0.16, green: 0.17, blue: 0.2)))
    }

    private static func drawBody(in context: GraphicsContext) {
        var body = Path()
        body.move(to: CGPoint(x: -52, y: 2))
        body.addCurve(to: CGPoint(x: 56, y: -22), control1: CGPoint(x: -36, y: -30), control2: CGPoint(x: 22, y: -34))
        body.addCurve(to: CGPoint(x: 60, y: 10), control1: CGPoint(x: 70, y: -14), control2: CGPoint(x: 72, y: 2))
        body.addCurve(to: CGPoint(x: -52, y: 2), control1: CGPoint(x: 32, y: 30), control2: CGPoint(x: -28, y: 24))
        body.closeSubpath()
        context.fill(body, with: .linearGradient(
            Gradient(colors: [Color(red: 0.58, green: 0.61, blue: 0.69), Color(red: 0.82, green: 0.84, blue: 0.89)]),
            startPoint: CGPoint(x: 0, y: -28), endPoint: CGPoint(x: 0, y: 24)))
        context.stroke(body, with: .color(.black.opacity(0.18)), lineWidth: 1)

        // Den skimrande halsen (grön–lila).
        let neck = Path(ellipseIn: CGRect(x: 36, y: -26, width: 30, height: 30))
        context.fill(neck, with: .linearGradient(
            Gradient(colors: [Color(red: 0.27, green: 0.62, blue: 0.52), Color(red: 0.55, green: 0.33, blue: 0.68)]),
            startPoint: CGPoint(x: 40, y: -24), endPoint: CGPoint(x: 62, y: 4)))

        let head = Path(ellipseIn: CGRect(x: 56, y: -42, width: 30, height: 28))
        context.fill(head, with: .color(Color(red: 0.52, green: 0.55, blue: 0.63)))

        var beak = Path()
        beak.move(to: CGPoint(x: 84, y: -32))
        beak.addQuadCurve(to: CGPoint(x: 99, y: -26), control: CGPoint(x: 93, y: -31))
        beak.addLine(to: CGPoint(x: 84, y: -24))
        beak.closeSubpath()
        context.fill(beak, with: .color(Color(red: 0.22, green: 0.22, blue: 0.25)))
        context.fill(Path(ellipseIn: CGRect(x: 82, y: -35, width: 7, height: 5)), with: .color(.white.opacity(0.9)))

        context.fill(Path(ellipseIn: CGRect(x: 71, y: -35, width: 8, height: 8)), with: .color(Color(red: 0.96, green: 0.52, blue: 0.1)))
        context.fill(Path(ellipseIn: CGRect(x: 73, y: -33, width: 4, height: 4)), with: .color(.black))
    }

    /// Vingen ritas uppåt-bakåt från axeln och skalas i höjdled efter vingslaget:
    /// uppe = full längd uppåt, utsträckt = kort (sedd från kanten), nere = under kroppen.
    private static func drawWing(in context: GraphicsContext, lift: CGFloat, offset: CGPoint, size: CGFloat, dark: Bool) {
        var wingContext = context
        wingContext.translateBy(x: shoulder.x + offset.x, y: shoulder.y + offset.y)
        // Vingen sveper lite bakåt när den slår ner.
        wingContext.rotate(by: .degrees(Double(-8 + 10 * lift)))
        let stretch = lift >= 0 ? max(0.14, lift) : min(-0.14, lift)
        wingContext.scaleBy(x: size, y: size * stretch)

        var wing = Path()
        wing.move(to: .zero)
        wing.addCurve(to: CGPoint(x: -8, y: -122), control1: CGPoint(x: 20, y: -40), control2: CGPoint(x: 12, y: -100))
        // Handpennorna – "fingrarna" längst ut.
        let fingers: [CGPoint] = [
            CGPoint(x: -28, y: -112), CGPoint(x: -24, y: -103), CGPoint(x: -44, y: -98),
            CGPoint(x: -39, y: -89), CGPoint(x: -60, y: -80), CGPoint(x: -53, y: -71),
            CGPoint(x: -72, y: -58)
        ]
        for point in fingers { wing.addLine(to: point) }
        wing.addCurve(to: CGPoint(x: -44, y: -6), control1: CGPoint(x: -74, y: -38), control2: CGPoint(x: -62, y: -14))
        wing.closeSubpath()

        let top = dark ? Color(red: 0.46, green: 0.49, blue: 0.56) : Color(red: 0.74, green: 0.77, blue: 0.83)
        let tip = dark ? Color(red: 0.32, green: 0.34, blue: 0.4) : Color(red: 0.5, green: 0.53, blue: 0.6)
        wingContext.fill(wing, with: .linearGradient(Gradient(colors: [top, tip]), startPoint: .zero, endPoint: CGPoint(x: -20, y: -120)))
        wingContext.stroke(wing, with: .color(.black.opacity(0.2)), lineWidth: 1)

        // Duvans två mörka vingband.
        if !dark {
            var bars = Path()
            bars.move(to: CGPoint(x: -10, y: -22))
            bars.addLine(to: CGPoint(x: -40, y: -28))
            bars.move(to: CGPoint(x: -6, y: -36))
            bars.addLine(to: CGPoint(x: -38, y: -42))
            wingContext.stroke(bars, with: .color(Color(red: 0.18, green: 0.19, blue: 0.22)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
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

/// Välkomstsidans LP: dra runt skivan med fingret så scratchar den – framåt och bakåt,
/// med ljud i samma takt. Släpper man stannar skivan.
struct ScratchRecord: View {
    var size: CGFloat = 180
    @State private var angle: Double = 0
    @State private var lastAngle: Double?
    @State private var lastTime: Date?
    @State private var updates = 0
    @State private var sound: ScratchSound?

    var body: some View {
        // Fingret mäts mot ramen runt skivan (som inte snurrar), inte mot skivan själv.
        ZStack {
            VectorRecord(angle: angle)
                .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
        }
        .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let center = CGPoint(x: size / 2, y: size / 2)
                        let current = atan2(Double(value.location.y - center.y), Double(value.location.x - center.x)) * 180 / .pi
                        let now = Date()
                        if sound == nil { sound = ScratchSound() }
                        sound?.start()
                        if let lastAngle, let lastTime {
                            var delta = current - lastAngle
                            if delta > 180 { delta -= 360 }
                            if delta < -180 { delta += 360 }
                            angle += delta
                            let seconds = max(now.timeIntervalSince(lastTime), 0.008)
                            // 33 varv/minut ≈ 200 grader/s = vanlig fart.
                            sound?.setRate(delta / seconds / 200)
                        }
                        lastAngle = current
                        lastTime = now
                        // Håller fingret still: tyst efter en kort stund.
                        updates += 1
                        let mark = updates
                        Task {
                            try? await Task.sleep(for: .milliseconds(70))
                            if updates == mark { sound?.setRate(0) }
                        }
                    }
                    .onEnded { _ in
                        lastAngle = nil
                        lastTime = nil
                        sound?.setRate(0)
                    }
            )
            .onDisappear {
                sound?.stop()
                sound = nil
            }
            .accessibilityLabel("Potpurri-skivan – dra runt för att scratcha")
    }
}

/// Skärmsläckaren i pauserna: loggan snurrar sakta på en skivspelare. Tryck var som
/// helst – skivan snurrar fort, krymper och lägger sig på loggans plats uppe till vänster.
struct ScreensaverView: View {
    let onClose: () -> Void
    @State private var started = Date()
    @State private var leaving: Date?
    private static let exitDuration = 0.75
    /// Grader per sekund – en lugn snurr.
    private static let speed = 40.0

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                let now = timeline.date
                let raw = leaving.map { min(1, now.timeIntervalSince($0) / Self.exitDuration) } ?? 0
                // Snabbt i början, mjukt in på plats.
                let exit = 1 - pow(1 - raw, 3)
                let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2 - 30)
                let recordSize = min(proxy.size.width, proxy.size.height) * 0.5
                let home = CGPoint(x: 39, y: 52)
                let spin = now.timeIntervalSince(started) * Self.speed + exit * 1080
                let fade = 1 - min(1, exit * 2)
                ZStack {
                    Color.black
                        .opacity(1 - exit)
                    TurntableBase(recordSize: recordSize)
                        .position(center)
                        .opacity(fade)
                    VectorRecord(angle: spin)
                        .frame(width: recordSize, height: recordSize)
                        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                        .scaleEffect(1 - (1 - 46 / recordSize) * exit)
                        .position(
                            x: center.x + (home.x - center.x) * exit,
                            y: center.y + (home.y - center.y) * exit
                        )
                    // Tonarmen ligger ovanpå skivan.
                    Tonearm(center: center, radius: recordSize / 2)
                        .opacity(fade)
                    Text(now, format: Date.FormatStyle(locale: Locale(identifier: "sv_SE")).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                        .font(.system(size: 54, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                        .position(x: center.x, y: center.y + recordSize * 0.5 + 100)
                        .opacity(1 - min(1, exit * 3))
                }
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {
            guard leaving == nil else { return }
            leaving = Date()
            Task {
                try? await Task.sleep(for: .seconds(Self.exitDuration))
                onClose()
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Skärmsläckare. Tryck för att fortsätta.")
    }
}

/// Skivspelarens chassi och tallrik (under skivan).
private struct TurntableBase: View {
    let recordSize: CGFloat

    var body: some View {
        let width = recordSize * 1.6
        let height = recordSize * 1.28
        ZStack {
            RoundedRectangle(cornerRadius: recordSize * 0.06)
                .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.1)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: recordSize * 0.06).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .frame(width: width, height: height)
                .offset(x: recordSize * 0.2)
            Circle()
                .fill(Color(white: 0.05))
                .frame(width: recordSize * 1.05, height: recordSize * 1.05)
        }
    }
}

/// Tonarmen: fästet uppe till höger, armen in över skivan och pickupen på skivans
/// yttre spår. Ritas ovanpå skivan.
private struct Tonearm: View {
    let center: CGPoint
    let radius: CGFloat

    var body: some View {
        Canvas { context, _ in
            let pivot = CGPoint(x: center.x + radius * 1.22, y: center.y - radius * 0.78)
            let needle = CGPoint(x: center.x + radius * 0.62, y: center.y + radius * 0.32)
            let elbow = CGPoint(x: needle.x + radius * 0.12, y: needle.y - radius * 0.3)
            // Motvikten bakom fästet.
            let back = CGPoint(x: pivot.x + (pivot.x - elbow.x) * 0.22, y: pivot.y + (pivot.y - elbow.y) * 0.22)
            var counterweight = Path()
            counterweight.move(to: pivot)
            counterweight.addLine(to: back)
            context.stroke(counterweight, with: .color(Color(white: 0.4)), style: StrokeStyle(lineWidth: radius * 0.11, lineCap: .round))

            context.fill(Path(ellipseIn: CGRect(x: pivot.x - radius * 0.14, y: pivot.y - radius * 0.14, width: radius * 0.28, height: radius * 0.28)), with: .color(Color(white: 0.3)))
            context.fill(Path(ellipseIn: CGRect(x: pivot.x - radius * 0.07, y: pivot.y - radius * 0.07, width: radius * 0.14, height: radius * 0.14)), with: .color(Color(white: 0.6)))

            var arm = Path()
            arm.move(to: pivot)
            arm.addLine(to: elbow)
            arm.addLine(to: needle)
            context.stroke(arm, with: .color(.black.opacity(0.4)), style: StrokeStyle(lineWidth: radius * 0.05, lineCap: .round, lineJoin: .round))
            context.stroke(arm, with: .linearGradient(Gradient(colors: [Color(white: 0.9), Color(white: 0.6)]), startPoint: pivot, endPoint: needle), style: StrokeStyle(lineWidth: radius * 0.035, lineCap: .round, lineJoin: .round))

            // Pickupen i armens riktning.
            let dx = needle.x - elbow.x
            let dy = needle.y - elbow.y
            let length = max(hypot(dx, dy), 1)
            let unit = CGPoint(x: dx / length, y: dy / length)
            var head = Path()
            head.move(to: CGPoint(x: needle.x - unit.x * radius * 0.1, y: needle.y - unit.y * radius * 0.1))
            head.addLine(to: CGPoint(x: needle.x + unit.x * radius * 0.04, y: needle.y + unit.y * radius * 0.04))
            context.stroke(head, with: .color(Color(white: 0.8)), style: StrokeStyle(lineWidth: radius * 0.09, lineCap: .butt))
        }
        .allowsHitTesting(false)
    }
}

/// Potpurri-skivan ritad som vektorgrafik – skarp i alla storlekar. Etiketten snurrar
/// (`angle`); spåren och ljusreflexen står still, som på en riktig skiva.
struct VectorRecord: View {
    var angle: Double = 0

    private static let grooves: [(radius: CGFloat, light: Bool)] = [
        (42.40, true), (41.65, false), (40.90, true), (40.15, false), (39.40, true), (38.65, false), (37.90, true),
        (35.85, true), (35.10, false), (34.35, true), (33.60, false), (32.85, true), (32.10, false),
        (30.05, false), (29.30, true), (28.55, false), (27.80, true), (27.05, false), (26.30, true),
        (24.25, true), (23.50, false), (22.75, true)
    ]

    /// Duvan på etiketten (samma som i appikonen).
    private static let dove: [CGPoint] = {
        let raw: [(Double, Double)] = [
        (80.0, 11.9), (77.5, 9.6), (74.5, 8.6), (71.5, 8.9), (68.4, 10.6), (66.7, 12.9), (66.2, 14.4), (65.9, 17.2),
        (66.4, 21.4), (66.2, 23.2), (65.2, 25.7), (60.7, 31.0), (53.2, 38.5), (9.3, 66.8), (1.0, 72.6), (17.0, 70.1),
        (31.8, 72.1), (45.6, 72.6), (50.9, 75.6), (51.9, 79.1), (51.6, 80.1), (46.6, 80.1), (46.9, 82.4), (61.4, 82.4),
        (61.4, 80.1), (54.9, 80.1), (54.2, 79.1), (53.2, 74.3), (56.2, 71.6), (61.4, 70.6), (64.9, 69.3), (68.2, 67.6),
        (70.5, 65.8), (74.2, 61.0), (76.0, 57.5), (77.7, 50.8), (77.7, 23.2), (79.5, 21.4), (80.2, 21.4), (87.0, 24.4),
        (81.2, 14.9)
            ]
        return raw.map { CGPoint(x: -15 + 0.3 * $0.0, y: -16 + 0.3 * $0.1) }
    }()

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 88
            var base = context
            base.translateBy(x: size.width / 2, y: size.height / 2)
            var disc = base
            disc.scaleBy(x: unit, y: unit)
            func circle(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)) }

            disc.fill(circle(44), with: .color(Color(red: 0.03, green: 0.03, blue: 0.04)))
            disc.stroke(circle(43.6), with: .color(Color(red: 0.35, green: 0.35, blue: 0.38)), lineWidth: 0.8)
            for groove in Self.grooves {
                let shade = groove.light ? Color(red: 0.2, green: 0.2, blue: 0.23) : Color(red: 0.15, green: 0.15, blue: 0.17)
                disc.stroke(circle(groove.radius), with: .color(shade), lineWidth: 0.3)
            }

            // Etiketten snurrar.
            var label = disc
            label.rotate(by: .degrees(angle))
            label.fill(circle(19.5), with: .color(Color(red: 0.984, green: 0.569, blue: 1)))
            label.stroke(circle(18.2), with: .color(.black.opacity(0.5)), lineWidth: 0.25)
            var dove = Path()
            dove.addLines(Self.dove)
            dove.closeSubpath()
            label.fill(dove, with: .color(Color(white: 0.07)))
            label.fill(circle(1.9), with: .color(Color(red: 0.15, green: 0.15, blue: 0.17)))
            label.stroke(circle(2.15), with: .color(Color(red: 0.984, green: 0.569, blue: 1)), lineWidth: 0.55)
            // Texten ritas i full storlek (inte uppskalad) så att den blir skarp.
            var text = base
            text.rotate(by: .degrees(angle))
            text.draw(
                Text("POTPURRI")
                    .font(.system(size: 2.5 * unit, weight: .semibold))
                    .tracking(0.6 * unit)
                    .foregroundStyle(Color(white: 0.07)),
                at: CGPoint(x: 0, y: 14.6 * unit)
            )

            // Ljusreflexen står still medan skivan snurrar.
            let sheen = GraphicsContext.Shading.linearGradient(
                Gradient(stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: .white.opacity(0.22), location: 0.5),
                    .init(color: .white.opacity(0), location: 1)
                ]),
                startPoint: CGPoint(x: -50, y: -50), endPoint: CGPoint(x: 50, y: 50)
            )
            for (from, to, opacity) in [(-80.0, -40.0, 0.9), (100.0, 140.0, 0.6)] {
                var wedge = Path()
                wedge.move(to: .zero)
                for step in 0...16 {
                    let degrees = from + (to - from) * Double(step) / 16
                    let radians = degrees * .pi / 180
                    wedge.addLine(to: CGPoint(x: 43 * cos(radians), y: 43 * sin(radians)))
                }
                wedge.closeSubpath()
                var shine = disc
                shine.opacity = opacity
                shine.fill(wedge, with: sheen)
            }
        }
        .accessibilityHidden(true)
    }
}
