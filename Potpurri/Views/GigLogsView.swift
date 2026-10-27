import SwiftData
import SwiftUI

/// Kvällsloggarna: vad som spelades, i ordning och med tid. Bra för att se vad som
/// spelades senast på samma ställe. En kväll kan bli en ny låtlista.
struct GigLogsList: View {
    @Query(sort: \GigLog.started, order: .reverse) private var logs: [GigLog]

    var body: some View {
        List {
            ForEach(logs.filter { !$0.entries.isEmpty }) { log in
                NavigationLink {
                    GigLogDetail(log: log)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(log.name)
                        Text(log.entries.count == 1 ? "1 låt" : "\(log.entries.count) låtar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if logs.allSatisfy({ $0.entries.isEmpty }) {
                ContentUnavailableView("Inga kvällsloggar än", systemImage: "music.note.list", description: Text("En låt hamnar i loggen när den har spelats i 30 sekunder."))
            }
        }
        .navigationTitle("Kvällsloggar")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GigLogDetail: View {
    @Bindable var log: GigLog
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var made = false

    var body: some View {
        List {
            Section("Namn") {
                TextField("Namn", text: $log.name)
            }
            Section("Spelade låtar") {
                ForEach(Array(log.entries.enumerated()), id: \.offset) { index, entry in
                    HStack {
                        Text("\(index + 1)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .trailing)
                        Text(entry.title)
                        Spacer()
                        Text(entry.time, format: Date.FormatStyle(locale: Locale(identifier: "sv_SE")).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button {
                    context.insert(Setlist(name: log.name, songIDs: log.entries.map(\.songID)))
                    made = true
                } label: {
                    Label("Gör låtlista av kvällen", systemImage: "text.badge.plus")
                }
                .disabled(made)
                Button("Ta bort loggen", role: .destructive) {
                    context.delete(log)
                    dismiss()
                }
            } footer: {
                if made { Text("Låtlistan \"\(log.name)\" finns nu under Låtlistor.") }
            }
        }
        .navigationTitle(log.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
