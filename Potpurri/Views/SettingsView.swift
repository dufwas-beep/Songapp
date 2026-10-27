import SwiftUI
import SwiftData

/// Kugghjulet uppe till höger – öppnar inställningarna.
struct SettingsButton: View {
    @State private var showsSettings = false

    var body: some View {
        Button {
            showsSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Inställningar")
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
    }
}

/// Inställningar: kvällsloggar och säkerhetskopia. Fler inställningar kan läggas till här.
struct SettingsView: View {
    @Environment(Player.self) private var player
    @Environment(ColorCodes.self) private var colorCodes
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var backupProgress = TaskProgress()
    @State private var exportedURL: URL?
    @State private var importing = false
    @State private var pendingRestore: (content: Backup.Content, archive: ZipArchive)?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Spelningar") {
                    NavigationLink {
                        GigLogsList()
                    } label: {
                        Label("Kvällsloggar", systemImage: "music.note.list")
                    }
                }
                Section {
                    Button {
                        Task { await export() }
                    } label: {
                        Label("Spara säkerhetskopia", systemImage: "externaldrive.badge.plus")
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("Läs in säkerhetskopia", systemImage: "externaldrive.badge.timemachine")
                    }
                    .disabled(player.isLocked)
                    if backupProgress.isRunning {
                        ProgressBanner(progress: backupProgress)
                    }
                } header: {
                    Text("Säkerhetskopia")
                } footer: {
                    Text("Sparar alla låtar, låtlistor, anteckningar och ljud i en fil som du lägger i Filer, t.ex. iCloud Drive.")
                }
                .disabled(backupProgress.isRunning)
            }
            .navigationTitle("Inställningar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") { dismiss() }
                }
            }
        }
        // Säkerhetskopian sparas där man väljer i Filer (t.ex. iCloud Drive eller Dropbox).
        .fileMover(isPresented: Binding(get: { exportedURL != nil }, set: { if !$0 { exportedURL = nil } }), file: exportedURL) { result in
            if case .success = result { message = "Säkerhetskopian är sparad." }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            guard case .success(let url) = result else { return }
            Task {
                do {
                    pendingRestore = try await Task.detached { try Backup.read(url) }.value
                } catch {
                    message = "Filen kunde inte läsas som en säkerhetskopia från Potpurri."
                }
            }
        }
        .confirmationDialog(
            "Ersätta allt med säkerhetskopian?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button("Ersätt allt", role: .destructive) {
                guard let pending = pendingRestore else { return }
                Task {
                    do {
                        try await Backup.restore(pending.content, archive: pending.archive, context: context, colorCodes: colorCodes, progress: backupProgress)
                        message = "Säkerhetskopian är inläst."
                    } catch {
                        message = "Det gick inte att läsa in säkerhetskopian: \(error.localizedDescription)"
                    }
                    pendingRestore = nil
                }
            }
        } message: {
            if let content = pendingRestore?.content {
                Text("Kopian från \(content.created.formatted(date: .abbreviated, time: .shortened)) har \(content.songs.count) låtar och \(content.setlists.count) låtlistor. Allt som finns i appen nu ersätts.")
            }
        }
        .alert("Säkerhetskopia", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func export() async {
        do {
            try context.save()
            exportedURL = try await Backup.export(context: context, colorNames: colorCodes.names, progress: backupProgress)
        } catch {
            message = "Säkerhetskopian kunde inte skapas: \(error.localizedDescription)"
        }
    }
}
