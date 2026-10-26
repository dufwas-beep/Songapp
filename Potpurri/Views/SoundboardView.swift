import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Soundboarden: en smal kolumn längs högerkanten med färgade ljudknappar.
/// Tryck = spela, tryck igen = stoppa direkt. "Redigera" överst, "Stoppa alla" längst ner.
struct SoundboardColumn: View {
    let engine: SoundEngine
    @Environment(\.modelContext) private var context
    @Environment(Player.self) private var player
    @Query(sort: \SoundClip.order) private var clips: [SoundClip]

    @State private var editing = false
    @State private var editingClip: SoundClip?
    @State private var importing = false
    @State private var ordering = false

    static let width: CGFloat = 124

    var body: some View {
        VStack(spacing: 8) {
            if !player.isLocked {
                Button(editing ? "Klar" : "Redigera") { editing.toggle() }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(editing ? .accentColor : .secondary)
                    .frame(maxWidth: .infinity)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(clips) { clip in
                        SoundButton(clip: clip, progress: engine.progress[clip.id], editing: editing) {
                            if editing { editingClip = clip } else { engine.toggle(clip) }
                        }
                    }
                    if editing {
                        Button {
                            importing = true
                        } label: {
                            Label("Ljud", systemImage: "plus")
                                .font(.footnote.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        Button {
                            ordering = true
                        } label: {
                            Label("Ordning", systemImage: "arrow.up.arrow.down")
                                .font(.footnote)
                                .frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.bordered)
                        .disabled(clips.count < 2)
                    }
                }
            }
            Button {
                engine.stopAll()
            } label: {
                Text("Stoppa alla")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(10)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .leading) { Divider() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            importSounds(urls)
        }
        .sheet(item: $editingClip) { clip in
            SoundEditor(clip: clip, engine: engine)
        }
        .sheet(isPresented: $ordering) {
            SoundOrderSheet()
        }
    }

    /// Ljudfiler från Filer (mp3, m4a, wav, aiff …) kopieras in i appen.
    private func importSounds(_ urls: [URL]) {
        var order = (clips.map(\.order).max() ?? -1) + 1
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let fileName = try? SongFileStore.importCopy(of: url) else { continue }
            let color = SoundClip.palette[order % SoundClip.palette.count]
            context.insert(SoundClip(name: url.deletingPathExtension().lastPathComponent, fileName: fileName, order: order, colorHex: color))
            order += 1
        }
    }
}

/// En ljudknapp med förloppsrand medan klippet spelas.
private struct SoundButton: View {
    let clip: SoundClip
    let progress: Double?
    let editing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(uiColor: UIColor(hex: clip.colorHex)))
                Text(clip.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let progress {
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(Color.black.opacity(0.45))
                            .frame(width: proxy.size.width * progress, height: 5)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .frame(height: 58)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(progress != nil ? Color.black : .clear, lineWidth: 3))
            .overlay(alignment: .topTrailing) {
                if editing {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(.black.opacity(0.6))
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(clip.name)
        .accessibilityHint(editing ? "Tryck för att redigera" : (progress != nil ? "Spelar – tryck för att stoppa" : "Tryck för att spela"))
    }
}

/// Redigera ett ljud: namn, färg, trimma start/slut på vågformen, volym, lyssna,
/// byt ljudfil och ta bort.
private struct SoundEditor: View {
    @Bindable var clip: SoundClip
    let engine: SoundEngine
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var peaks: [Float] = []
    @State private var duration: Double = 0
    @State private var replacing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Namn") {
                    TextField("Namn", text: $clip.name)
                }
                Section("Färg") {
                    HStack(spacing: 12) {
                        ForEach(SoundClip.palette, id: \.self) { hex in
                            Button {
                                clip.colorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(uiColor: UIColor(hex: hex)))
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().stroke(clip.colorHex == hex ? Color.primary : .clear, lineWidth: 3))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Färg")
                        }
                    }
                }
                Section("Trimma – dra i markörerna") {
                    TrimView(peaks: peaks, duration: duration, start: $clip.trimStart, end: Binding(
                        get: { clip.trimEnd > 0 ? clip.trimEnd : duration },
                        set: { clip.trimEnd = $0 }
                    ))
                    .frame(height: 110)
                    HStack {
                        Text("Start \(format(clip.trimStart))")
                        Spacer()
                        Text("Slut \(format(clip.trimEnd > 0 ? clip.trimEnd : duration))")
                    }
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                Section("Volym") {
                    HStack {
                        Slider(value: $clip.volumeDB, in: -12...6, step: 0.5)
                        Text(String(format: "%+.1f dB", clip.volumeDB))
                            .monospacedDigit()
                            .frame(width: 76, alignment: .trailing)
                    }
                }
                Section {
                    Button {
                        engine.toggle(clip)
                    } label: {
                        Label(engine.isPlaying(clip) ? "Stoppa" : "Förhandslyssna", systemImage: engine.isPlaying(clip) ? "stop.fill" : "play.fill")
                    }
                    Button {
                        replacing = true
                    } label: {
                        Label("Byt ljudfil", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button("Ta bort ljudet", role: .destructive) {
                        engine.stop(clip.id)
                        SongFileStore.delete(clip.fileName)
                        context.delete(clip)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Redigera ljud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") { dismiss() }
                }
            }
            .task(id: clip.fileName) { await loadWaveform() }
            .fileImporter(isPresented: $replacing, allowedContentTypes: [.audio]) { result in
                guard case .success(let url) = result else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                if let fileName = try? SongFileStore.importCopy(of: url) {
                    SongFileStore.delete(clip.fileName)
                    clip.fileName = fileName
                    clip.trimStart = 0
                    clip.trimEnd = 0
                }
            }
        }
    }

    private func loadWaveform() async {
        let url = clip.fileURL
        let result = await Task.detached(priority: .userInitiated) { SoundEngine.waveform(of: url) }.value
        peaks = result.peaks
        duration = result.duration
    }

    private func format(_ seconds: Double) -> String {
        String(format: "%d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }
}

/// Vågformen med två markörer för start och slut.
private struct TrimView: View {
    let peaks: [Float]
    let duration: Double
    @Binding var start: Double
    @Binding var end: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let x = { (time: Double) in duration > 0 ? CGFloat(time / duration) * width : 0 }
            ZStack(alignment: .leading) {
                HStack(alignment: .center, spacing: 1) {
                    ForEach(Array(peaks.enumerated()), id: \.offset) { _, peak in
                        Capsule()
                            .fill(Color.secondary.opacity(0.6))
                            .frame(height: max(2, CGFloat(peak) * proxy.size.height * 0.9))
                    }
                }
                .frame(maxHeight: .infinity)
                Rectangle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: max(0, x(end) - x(start)))
                    .offset(x: x(start))
                    .allowsHitTesting(false)
                marker(at: x(start)) { location in
                    start = min(max(0, Double(location / width) * duration), end - 0.1)
                }
                marker(at: x(end)) { location in
                    end = max(min(duration, Double(location / width) * duration), start + 0.1)
                }
            }
            .coordinateSpace(name: "trim")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trimning")
    }

    private func marker(at position: CGFloat, onDrag: @escaping (CGFloat) -> Void) -> some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 4)
            .overlay(alignment: .top) {
                Circle().fill(Color.accentColor).frame(width: 18, height: 18)
            }
            .frame(width: 44)
            .contentShape(Rectangle())
            .offset(x: position - 22)
            .gesture(DragGesture(coordinateSpace: .named("trim")).onChanged { onDrag($0.location.x) })
    }
}

/// Ändra ljudens ordning genom att dra dem.
private struct SoundOrderSheet: View {
    @Query(sort: \SoundClip.order) private var clips: [SoundClip]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(clips) { clip in
                    HStack {
                        Circle().fill(Color(uiColor: UIColor(hex: clip.colorHex))).frame(width: 16, height: 16)
                        Text(clip.name)
                    }
                }
                .onMove { from, to in
                    var ordered = clips
                    ordered.move(fromOffsets: from, toOffset: to)
                    for (index, clip) in ordered.enumerated() { clip.order = index }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Ljudens ordning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") { dismiss() }
                }
            }
        }
    }
}
