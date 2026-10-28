import SwiftData
import SwiftUI

/// Idélådan: skriv fritt – låtförslag man fått, kablar att köpa, något att testa eller
/// förbättringar för appen. Varje rad hamnar automatiskt i en kategori.
struct IdeaBoxView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Idea.created, order: .reverse) private var ideas: [Idea]
    @State private var draft = ""
    @State private var showsDone = false
    @State private var lastAdded: Idea?
    @FocusState private var writing: Bool

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        TextField("Låtförslag, något att köpa, testa eller komma ihåg …", text: $draft, axis: .vertical)
                            .lineLimit(1...4)
                            .focused($writing)
                            .onSubmit(add)
                        Button("Lägg till", action: add)
                            .buttonStyle(.borderedProminent)
                            .foregroundStyle(.black)
                            .disabled(trimmed.isEmpty)
                    }
                    if !trimmed.isEmpty {
                        let guess = IdeaCategory.guess(for: trimmed)
                        Label("Hamnar under \(guess.title)", systemImage: guess.symbol)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Kategorin väljs utifrån orden – \"köp\", \"repa\", \"testa\", \"appen\" … Håll in en rad för att flytta den.")
                }
                ForEach(IdeaCategory.allCases) { category in
                    let rows = ideas.filter { $0.category == category && (showsDone || !$0.done) }
                    if !rows.isEmpty {
                        Section {
                            ForEach(rows) { idea in
                                row(idea)
                            }
                        } header: {
                            Label("\(category.title) (\(rows.count))", systemImage: category.symbol)
                        }
                    }
                }
            }
            .navigationTitle("Idélådan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Toggle(isOn: $showsDone) {
                        Label("Visa klara", systemImage: "checkmark.circle")
                    }
                    ShareLink(item: exportText) {
                        Label("Dela", systemImage: "square.and.arrow.up")
                    }
                    .disabled(ideas.isEmpty)
                }
            }
            .onAppear { writing = true }
        }
    }

    private func row(_ idea: Idea) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                idea.done.toggle()
                try? context.save()
            } label: {
                Image(systemName: idea.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(idea.done ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(idea.done ? "Markera som inte klar" : "Markera som klar")
            VStack(alignment: .leading, spacing: 2) {
                Text(idea.text)
                    .strikethrough(idea.done)
                    .foregroundStyle(idea.done ? .secondary : .primary)
                Text(idea.created.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .listRowBackground(lastAdded?.id == idea.id ? Color.accentColor.opacity(0.15) : nil)
        .contextMenu {
            Menu {
                ForEach(IdeaCategory.allCases) { category in
                    Button {
                        idea.category = category
                        try? context.save()
                    } label: {
                        Label(category.title, systemImage: category.symbol)
                    }
                }
            } label: {
                Label("Flytta till", systemImage: "folder")
            }
            Button(role: .destructive) {
                context.delete(idea)
                try? context.save()
            } label: {
                Label("Ta bort", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                context.delete(idea)
                try? context.save()
            } label: {
                Label("Ta bort", systemImage: "trash")
            }
        }
    }

    private func add() {
        guard !trimmed.isEmpty else { return }
        let idea = Idea(text: trimmed, category: IdeaCategory.guess(for: trimmed))
        context.insert(idea)
        try? context.save()
        lastAdded = idea
        draft = ""
        writing = true
    }

    /// Hela lådan som text (t.ex. för att skicka förbättringarna för appen vidare).
    private var exportText: String {
        IdeaCategory.allCases.compactMap { category -> String? in
            let rows = ideas.filter { $0.category == category && !$0.done }
            guard !rows.isEmpty else { return nil }
            return category.title.uppercased() + "\n" + rows.map { "• " + $0.text }.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }
}
