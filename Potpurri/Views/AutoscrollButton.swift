import SwiftUI

/// Den runda autoscrollknappen i hörnet: visar låtens längd och en ring som fylls i takt
/// med låten. Tryck = starta/pausa. Håll in = reglage för låtens längd.
struct AutoscrollButton: View {
    let autoscroller: Autoscroller
    @Binding var seconds: Int
    @State private var showsLength = false

    var body: some View {
        ZStack {
            Circle()
                .fill(autoscroller.isRunning ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.regularMaterial))
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 4)
                .padding(3)
            Circle()
                .trim(from: 0, to: autoscroller.progress)
                .stroke(autoscroller.isRunning ? Color.black : Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3)
            VStack(spacing: 2) {
                Image(systemName: autoscroller.isRunning ? "pause.fill" : "arrow.down")
                    .font(.system(size: 18, weight: .semibold))
                Text(Self.format(seconds))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(autoscroller.isRunning ? Color.black : Color.primary)
        }
        .frame(width: 76, height: 76)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .contentShape(Circle())
        .onTapGesture {
            autoscroller.toggle()
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            showsLength = true
        }
        .popover(isPresented: $showsLength, arrowEdge: .trailing) {
            LengthPanel(seconds: $seconds)
        }
        .accessibilityElement()
        .accessibilityLabel(autoscroller.isRunning ? "Pausa autoscroll" : "Starta autoscroll")
        .accessibilityValue("Låtens längd \(Self.format(seconds))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { autoscroller.toggle() }
    }

    static func format(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Reglaget för låtens längd, 0:30–5:00. Dra åt höger för längre. Steg om en sekund
/// så att det går mjukt att dra.
private struct LengthPanel: View {
    @Binding var seconds: Int
    /// Värdet medan man drar – sparas först när man släpper, så att reglaget går mjukt.
    @State private var value: Double = 180

    var body: some View {
        VStack(spacing: 14) {
            Text("Låtens längd")
                .font(.headline)
            Text(AutoscrollButton.format(Int(value.rounded())))
                .font(.system(size: 44, weight: .semibold))
                .monospacedDigit()
            Slider(value: $value, in: 30...300) {
                Text("Låtens längd")
            } minimumValueLabel: {
                Text("0:30").font(.caption)
            } maximumValueLabel: {
                Text("5:00").font(.caption)
            } onEditingChanged: { editing in
                if !editing { seconds = Int(value.rounded()) }
            }
            Text("Dra åt höger för längre, åt vänster för kortare. Sparas för låten.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 360)
        .onAppear { value = Double(min(max(seconds, 30), 300)) }
        .onDisappear { seconds = Int(value.rounded()) }
    }
}
