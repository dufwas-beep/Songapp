import SwiftUI
import UIKit

/// Vänsterspalten: LP-loggan, klockan och flikarna Låtlistor och Bibliotek.
struct SidebarView: View {
    @Binding var selection: Song?
    @AppStorage("sidebarTab") private var tab = SidebarTab.setlists
    /// Medan tangentbordet är uppe (t.ex. vid sökning) döljs Next-rutan så att listan syns.
    @State private var keyboardVisible = false

    enum SidebarTab: String {
        case setlists
        case library
    }

    var body: some View {
        // Listan och Next-rutan delar på höjden: krymper Next-rutan växer listan.
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .setlists:
                    SetlistsView(selection: $selection)
                case .library:
                    LibraryView(selection: $selection)
                }
            }
            .frame(maxHeight: .infinity)
            if !keyboardVisible {
                NextPanel(selection: selection)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardVisible = false }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 12) {
                SidebarHeader()
                Picker("Visa", selection: $tab) {
                    Text("Låtlistor").tag(SidebarTab.setlists)
                    Text("Bibliotek").tag(SidebarTab.library)
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(.bar)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// LP-loggan, namnet och en stor klocka (TT:MM). Håll in LP:n för scenlås.
private struct SidebarHeader: View {
    @Environment(Player.self) private var player
    @State private var angle: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            Image("LPLogo")
                .resizable()
                .frame(width: 46, height: 46)
                .rotationEffect(.degrees(angle))
                // Snurrar långsamt under autoscroll och stannar mjukt vid paus.
                .onChange(of: player.isAutoscrolling) { _, running in
                    if running {
                        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) { angle += 360 }
                    } else {
                        withAnimation(.easeOut(duration: 1.2)) { angle += 40 }
                    }
                }
                // Snabb snurr vid "Ny spelning" och lyckohjulet.
                .onChange(of: player.spinBurst) {
                    withAnimation(.easeOut(duration: 1.4)) { angle += 1080 }
                }
                // Tryck = lyckohjulet (slumpa en låt bland förslagen), dubbeltryck = duvan flyger.
                .onTapGesture(count: 2) {
                    player.doveFlights += 1
                }
                .onTapGesture {
                    player.spinBurst += 1
                    player.lotteryRuns += 1
                }
                .overlay {
                    if player.isLocked {
                        Circle().stroke(Color.accentColor, lineWidth: 3)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12, weight: .bold))
                            .padding(4)
                            .background(Color.accentColor, in: Circle())
                            .foregroundStyle(.black)
                            .offset(x: 16, y: 16)
                    }
                }
                .onLongPressGesture(minimumDuration: 0.8) {
                    withAnimation { player.isLocked.toggle() }
                }
                .accessibilityLabel(player.isLocked ? "Potpurri, scenlåset är på" : "Potpurri")
                .accessibilityHint("Håll in för att slå på eller av scenlåset")
                .accessibilityAction(named: player.isLocked ? "Lås upp" : "Scenlås") {
                    player.isLocked.toggle()
                }
            VStack(alignment: .leading, spacing: 0) {
                Text("POTPURRI")
                    .font(.system(size: 20, weight: .medium))
                    .tracking(1.2)
                Text("av Duva Event")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: Date.FormatStyle(locale: Locale(identifier: "sv_SE")).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                        .font(.system(size: 32, weight: .medium))
                        .monospacedDigit()
                        .accessibilityLabel("Klockan")
                }
                SetTimerButton()
            }
        }
    }
}

/// Nedräkning under klockan, t.ex. hur länge setet har kvar. Tryck för att starta
/// (upp till 60 minuter) eller stoppa.
struct SetTimerButton: View {
    @Environment(Player.self) private var player
    @State private var showsPicker = false

    var body: some View {
        Button {
            showsPicker = true
        } label: {
            if let end = player.timerEnd {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, Int(end.timeIntervalSince(context.date).rounded(.up)))
                    Text(String(format: "%d:%02d", left / 60, left % 60))
                        .font(.system(size: 17, weight: .semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(left == 0 ? Color.accentColor : Color.accentColor.opacity(0.2), in: Capsule())
                        .foregroundStyle(left == 0 ? Color.black : Color.primary)
                        .accessibilityLabel(left == 0 ? "Timern är slut" : "Timer, \(left / 60) minuter och \(left % 60) sekunder kvar")
                }
            } else {
                Label("Timer", systemImage: "timer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsPicker) {
            TimerPicker()
        }
    }
}

private struct TimerPicker: View {
    @Environment(Player.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Double = 45

    var body: some View {
        VStack(spacing: 16) {
            Text("Nedräkning")
                .font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                ForEach([5, 10, 15, 20, 30, 40, 45, 60], id: \.self) { value in
                    Button("\(value) min") { start(Double(value)) }
                        .buttonStyle(.bordered)
                }
            }
            HStack {
                Slider(value: $minutes, in: 1...60, step: 1)
                Text("\(Int(minutes)) min")
                    .monospacedDigit()
                    .frame(width: 64, alignment: .trailing)
            }
            HStack {
                if player.timerEnd != nil {
                    Button("Stoppa timern", role: .destructive) {
                        player.timerEnd = nil
                        dismiss()
                    }
                }
                Spacer()
                Button("Starta \(Int(minutes)) min") { start(minutes) }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(.black)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func start(_ minutes: Double) {
        player.timerEnd = Date().addingTimeInterval(minutes * 60)
        dismiss()
    }
}

/// Next-rutan med handtaget och "Ny spelning". Höjden ändras här inne medan man drar
/// och sparas när man släpper, så att listorna ovanför inte ritas om vid varje rörelse.
private struct NextPanel: View {
    let selection: Song?
    @AppStorage("suggestionsHeight") private var suggestionsHeight: Double = 260
    @State private var liveHeight: Double?
    @State private var dragStartHeight: Double?

    var body: some View {
        VStack(spacing: 10) {
            // Dra i handtaget för att göra Next-rutan större eller mindre.
            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 56, height: 5)
                .frame(maxWidth: .infinity, minHeight: 22)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(coordinateSpace: .global)
                        .onChanged { value in
                            let start = dragStartHeight ?? suggestionsHeight
                            dragStartHeight = start
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                liveHeight = min(max(start - value.translation.height, 90), 560)
                            }
                        }
                        .onEnded { _ in
                            if let liveHeight { suggestionsHeight = liveHeight }
                            liveHeight = nil
                            dragStartHeight = nil
                        }
                )
                .accessibilityLabel("Ändra storlek på Next-rutan")
            SuggestionsBox(current: selection)
                .frame(height: liveHeight ?? suggestionsHeight)
            GigFooter()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .background(.bar)
    }
}
