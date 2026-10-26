import SwiftUI

/// Statusfält som visas medan något importeras: förlopp, antal och ungefärlig tid kvar.
struct ProgressBanner: View {
    let progress: TaskProgress

    var body: some View {
        // Uppdateras varje sekund så att tiden kvar rör sig även när en stor fil laddas ner.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 12) {
            if progress.total > 0 {
                ImportArm(fraction: progress.fraction)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(progress.title)
                        .font(.headline)
                    Spacer()
                    if progress.total > 0 {
                        Text("\(progress.done) av \(progress.total)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                // Utan känt antal (t.ex. när backupfilen hämtas) visas en snurra.
                if progress.total > 0 {
                    ProgressView(value: progress.fraction)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Text(progress.currentName)
                        .lineLimit(1)
                    Spacer()
                    Text(progress.remainingText(at: context.date))
                        .monospacedDigit()
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(10)
        }
        .accessibilityElement(children: .combine)
    }
}
