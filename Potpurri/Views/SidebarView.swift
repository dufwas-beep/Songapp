import SwiftUI

/// Vänsterspalten: LP-loggan, klockan och flikarna Låtlistor och Bibliotek.
struct SidebarView: View {
    @Binding var selection: Song?
    @AppStorage("sidebarTab") private var tab = SidebarTab.setlists

    enum SidebarTab: String {
        case setlists
        case library
    }

    var body: some View {
        Group {
            switch tab {
            case .setlists:
                SetlistsView(selection: $selection)
            case .library:
                LibraryView(selection: $selection)
            }
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

    var body: some View {
        HStack(spacing: 12) {
            Image("LPLogo")
                .resizable()
                .frame(width: 46, height: 46)
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
            TimelineView(.everyMinute) { context in
                Text(context.date, format: Date.FormatStyle(locale: Locale(identifier: "sv_SE")).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(.system(size: 32, weight: .medium))
                    .monospacedDigit()
                    .accessibilityLabel("Klockan")
            }
        }
    }
}
