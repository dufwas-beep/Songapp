import SwiftData
import SwiftUI

/// Idélådan: skriv fritt – låtförslag man fått, kablar att köpa, något att testa eller
/// förbättringar för appen. Varje rad hamnar automatiskt i en kategori. Alla kategorier
/// finns alltid; håll in en rad och dra den till en annan kategori (eller välj "Flytta
/// till" i menyn som kommer när man håller in). Tryck för att ändra.
struct IdeaBoxView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Idea.created, order: .reverse) private var ideas: [Idea]
    @State private var draft = ""
    @State private var showsDone = false
    @State private var lastAdded: UUID?
    @State private var editing: Idea?
    @State private var dropTarget: IdeaCategory?
    @FocusState private var writing: Bool

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            // Egen lista i stället för iPadens: i den inbyggda kom släppen aldrig fram till
            // kategorierna. Hela kategorirutan tar emot en rad som dras dit.
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(IdeaCategory.allCases) { category in
                        section(category)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            // Skrivfältet ligger fast ovanför listan, så att inget hoppar medan man skriver.
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        TextField("Låtförslag, något att köpa, testa eller komma ihåg …", text: $draft)
                            .textFieldStyle(.roundedBorder)
                            .focused($writing)
                            .submitLabel(.done)
                            .onSubmit(add)
                        Button("Lägg till", action: add)
                            .buttonStyle(.borderedProminent)
                            .foregroundStyle(.black)
                            .disabled(trimmed.isEmpty)
                    }
                    let guess = IdeaCategory.guess(for: trimmed)
                    Label(trimmed.isEmpty ? "Tryck på en rad för att ändra eller ta bort den. Håll in och dra för att flytta." : "Hamnar under \(guess.title)",
                          systemImage: trimmed.isEmpty ? "hand.tap" : guess.symbol)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
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
            .sheet(item: $editing) { idea in
                IdeaEditor(idea: idea)
            }
        }
    }

    private func section(_ category: IdeaCategory) -> some View {
        let rows = ideas.filter { $0.category == category && (showsDone || !$0.done) }
        let targeted = dropTarget == category
        return VStack(alignment: .leading, spacing: 0) {
            Label("\(category.title) (\(rows.count))", systemImage: category.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(targeted ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            ForEach(rows) { idea in
                Divider().padding(.leading, 16)
                row(idea)
            }
            if rows.isEmpty {
                Divider().padding(.leading, 16)
                Text(targeted ? "Släpp här" : "Dra hit en rad")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor, lineWidth: targeted ? 3 : 0)
        }
        .scaleEffect(targeted ? 1.01 : 1)
        .animation(.easeOut(duration: 0.15), value: targeted)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .dropDestination(for: String.self) { items, _ in
            move(items, to: category)
        } isTargeted: { target(category, $0) }
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
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(lastAdded == idea.id ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        // Tryck = ändra texten, kategorin eller ta bort.
        .onTapGesture { editing = idea }
        .draggable("idea:" + idea.id.uuidString) {
            Text(idea.text)
                .lineLimit(2)
                .padding(10)
                .frame(maxWidth: 320, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .contextMenu {
            Menu {
                ForEach(IdeaCategory.allCases.filter { $0 != idea.category }) { category in
                    Button {
                        idea.category = category
                        try? context.save()
                    } label: {
                        Label(category.title, systemImage: category.symbol)
                    }
                }
            } label: {
                Label("Flytta till", systemImage: "arrow.right.square")
            }
            Button {
                editing = idea
            } label: {
                Label("Ändra", systemImage: "pencil")
            }
            Button(role: .destructive) {
                delete(idea)
            } label: {
                Label("Ta bort", systemImage: "trash")
            }
        }
    }

    private func target(_ category: IdeaCategory, _ targeted: Bool) {
        if targeted {
            dropTarget = category
        } else if dropTarget == category {
            dropTarget = nil
        }
    }

    /// En rad släpps i en kategori.
    private func move(_ items: [String], to category: IdeaCategory) -> Bool {
        dropTarget = nil
        let ids = items.compactMap { $0.hasPrefix("idea:") ? UUID(uuidString: String($0.dropFirst(5))) : nil }
        guard !ids.isEmpty else { return false }
        for idea in ideas where ids.contains(idea.id) {
            idea.category = category
        }
        try? context.save()
        return true
    }

    private func delete(_ idea: Idea) {
        context.delete(idea)
        try? context.save()
    }

    private func add() {
        guard !trimmed.isEmpty else { return }
        let idea = Idea(text: trimmed, category: IdeaCategory.guess(for: trimmed))
        context.insert(idea)
        try? context.save()
        lastAdded = idea.id
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

/// Ändra en rad i Idélådan: texten och kategorin, eller ta bort den.
private struct IdeaEditor: View {
    @Bindable var idea: Idea
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var category = IdeaCategory.remember
    @State private var confirmsDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    TextField("Text", text: $text, axis: .vertical)
                        .lineLimit(3...10)
                }
                Section("Kategori") {
                    Picker("Kategori", selection: $category) {
                        ForEach(IdeaCategory.allCases) { category in
                            Label(category.title, systemImage: category.symbol).tag(category)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    Button("Ta bort", role: .destructive) {
                        confirmsDelete = true
                    }
                }
            }
            .navigationTitle("Ändra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { idea.text = trimmed }
                        idea.category = category
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Ta bort raden?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Ta bort", role: .destructive) {
                    context.delete(idea)
                    try? context.save()
                    dismiss()
                }
            }
            .onAppear {
                text = idea.text
                category = idea.category
            }
        }
    }
}
