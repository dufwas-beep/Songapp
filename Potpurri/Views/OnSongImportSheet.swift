import SwiftUI

/// Listan med låtarna i en OnSong-backup. Man kryssar i vilka som ska importeras;
/// låtar som redan finns i Potpurri är urkryssade från början.
struct OnSongImportSheet: View {
    let backup: OnSongBackup
    let onImport: (Set<String>) -> Void
    let onCancel: () -> Void

    @State private var selected: Set<String>
    @State private var query = ""

    init(backup: OnSongBackup, onImport: @escaping (Set<String>) -> Void, onCancel: @escaping () -> Void) {
        self.backup = backup
        self.onImport = onImport
        self.onCancel = onCancel
        _selected = State(initialValue: Set(backup.candidates.filter { !$0.alreadyExists }.map(\.id)))
    }

    private var visible: [OnSongCandidate] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? backup.candidates : backup.candidates.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(visible) { candidate in
                        Button {
                            toggle(candidate.id)
                        } label: {
                            CandidateRow(candidate: candidate, isSelected: selected.contains(candidate.id))
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(headerText)
                }
            }
            .searchable(text: $query, prompt: "Sök låt")
            .navigationTitle("Importera från OnSong")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importera \(selected.count)") {
                        onImport(selected)
                    }
                    .disabled(selected.isEmpty)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Markera alla") {
                        selected.formUnion(visible.map(\.id))
                    }
                    Spacer()
                    Button("Avmarkera alla") {
                        selected.subtract(visible.map(\.id))
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var headerText: String {
        let existing = backup.candidates.filter(\.alreadyExists).count
        var text = "\(backup.candidates.count) låtar i backupen"
        if existing > 0 { text += " · \(existing) finns redan (urkryssade)" }
        if !backup.setlists.isEmpty { text += " · \(backup.setlists.count) låtlistor följer med" }
        return text
    }

    private func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }
}

private struct CandidateRow: View {
    let candidate: OnSongCandidate
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(candidate.title)
                        .lineLimit(1)
                    if candidate.kind == .note {
                        Image(systemName: "note.text")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Anteckning")
                    }
                }
                if candidate.alreadyExists {
                    Text("Finns redan i Potpurri")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let key = candidate.key {
                Text(key)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
