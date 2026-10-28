import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Kugghjulet uppe till höger – öppnar inställningarna.
struct SettingsButton: View {
    var size: CGFloat = 44
    @State private var showsSettings = false

    var body: some View {
        Button {
            showsSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: size * 0.42, weight: .semibold))
                .frame(width: size, height: size)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
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
    @State private var choosingFolder = false
    /// Vad filväljaren är öppen för (finns kvar när den stängs, till svaret).
    @State private var pickingFolder = false
    @State private var autoFolder = AutoBackup.folderName
    @State private var autoLast = AutoBackup.lastBackup
    @State private var confirmsRemoveTestSongs = false
    @AppStorage("appearance") private var appearance = Appearance.system
    @AppStorage("grayTone") private var grayTone = Theme.defaultTone
    @AppStorage("showsSwitchTimer") private var showsSwitchTimer = false
    @Query private var songs: [Song]

    private var testSongs: [Song] { songs.filter(TestSongs.isTestSong) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Utseende") {
                    Picker("Läge", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if appearance == .gray {
                        HStack {
                            Text("Mörkare")
                            Slider(value: $grayTone, in: 0.18...0.42)
                            Text("Ljusare")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
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
                        pickingFolder = false
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
                Section {
                    Button {
                        pickingFolder = true
                        choosingFolder = true
                    } label: {
                        LabeledContent {
                            Text(autoFolder ?? "Av")
                        } label: {
                            Label("Varje vecka till mappen", systemImage: "folder.badge.gearshape")
                        }
                    }
                    if autoFolder != nil {
                        Button {
                            Task {
                                do {
                                    try await AutoBackup.runIfDue(context: context, colorNames: colorCodes.names, force: true)
                                    autoLast = AutoBackup.lastBackup
                                    message = "Säkerhetskopian är sparad i \(autoFolder ?? "mappen")."
                                } catch {
                                    message = "Kunde inte spara i mappen: \(error.localizedDescription). Välj mappen igen."
                                }
                            }
                        } label: {
                            Label("Spara en kopia dit nu", systemImage: "arrow.clockwise")
                        }
                        Button("Stäng av automatisk kopia", role: .destructive) {
                            AutoBackup.turnOff()
                            autoFolder = nil
                        }
                    }
                } header: {
                    Text("Automatisk säkerhetskopia")
                } footer: {
                    if let autoLast {
                        Text("Senast: \(autoLast.formatted(date: .abbreviated, time: .shortened)). De fyra senaste kopiorna sparas.")
                    } else {
                        Text("Välj en mapp i Filer, t.ex. samma som du sparat i förut. En kopia sparas när appen öppnas och det gått en vecka sedan sist. De fyra senaste sparas.")
                    }
                }
                .disabled(backupProgress.isRunning)
                Section {
                    NavigationLink {
                        FeaturesList()
                    } label: {
                        Label("Funktioner", systemImage: "switch.2")
                    }
                } footer: {
                    Text("Stäng av delar du inte använder, så blir appen renare.")
                }
                Section("Hjälp") {
                    Button {
                        // Guiden visas ovanpå appen, så inställningarna stängs först.
                        dismiss()
                        Task {
                            try? await Task.sleep(for: .milliseconds(600))
                            player.guideChooserOpen = true
                        }
                    } label: {
                        Label("Visa guiden", systemImage: "questionmark.circle")
                    }
                }
                Section {
                    Toggle(isOn: $showsSwitchTimer) {
                        Label("Visa tid för låtbyte", systemImage: "stopwatch")
                    }
                    Button {
                        TestSongs.add(200, to: context, existing: songs.count)
                    } label: {
                        Label("Lägg till 200 testlåtar", systemImage: "plus.square.on.square")
                    }
                    Button(role: .destructive) {
                        confirmsRemoveTestSongs = true
                    } label: {
                        Label("Ta bort testlåtarna (\(testSongs.count))", systemImage: "trash")
                    }
                    .disabled(testSongs.isEmpty)
                } header: {
                    Text("Prestandatest")
                } footer: {
                    Text("Testlåtarna heter ”Testlåt …” och kan tas bort här när du har provat.")
                }
                .disabled(player.isLocked)
            }
            .themedBackground()
            .navigationTitle("Inställningar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") { dismiss() }
                }
            }
        }
        .confirmationDialog("Ta bort \(testSongs.count) testlåtar?", isPresented: $confirmsRemoveTestSongs, titleVisibility: .visible) {
            Button("Ta bort", role: .destructive) {
                // Inställningarna stängs först; själva borttagningen görs i ContentView
                // så att ingen vy håller kvar en borttagen låt.
                player.songsToDelete = Set(testSongs.map(\.id))
                dismiss()
            }
        }
        // Säkerhetskopian sparas där man väljer i Filer (t.ex. iCloud Drive eller Dropbox).
        .fileMover(isPresented: Binding(get: { exportedURL != nil }, set: { if !$0 { exportedURL = nil } }), file: exportedURL) { result in
            if case .success = result { message = "Säkerhetskopian är sparad." }
        }
        // En enda filväljare (två i samma vy krånglar): säkerhetskopia att läsa in eller mapp.
        .fileImporter(
            isPresented: Binding(get: { importing || choosingFolder }, set: { if !$0 { importing = false; choosingFolder = false } }),
            allowedContentTypes: pickingFolder ? [.folder] : [.data]
        ) { result in
            guard case .success(let url) = result else { return }
            if pickingFolder {
                chooseFolder(url)
                return
            }
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

    private func chooseFolder(_ url: URL) {
        do {
            try AutoBackup.setFolder(url)
            autoFolder = AutoBackup.folderName
            Task {
                try? await AutoBackup.runIfDue(context: context, colorNames: colorCodes.names)
                autoLast = AutoBackup.lastBackup
            }
        } catch {
            message = "Mappen kunde inte väljas: \(error.localizedDescription)"
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

/// Slå av och på delar av appen.
private struct FeaturesList: View {
    var body: some View {
        Form {
            Section {
                ForEach(Feature.allCases) { feature in
                    FeatureToggle(feature: feature)
                }
            } footer: {
                Text("Det du stänger av döljs bara – inget tas bort, och allt kommer tillbaka när du slår på det igen.")
            }
        }
        .navigationTitle("Funktioner")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FeatureToggle: View {
    let feature: Feature
    @AppStorage private var isOn: Bool

    init(feature: Feature) {
        self.feature = feature
        _isOn = AppStorage(wrappedValue: true, feature.key)
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(feature.title, systemImage: feature.symbol)
        }
    }
}
