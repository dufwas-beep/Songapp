import AVFoundation
import Observation

/// Spelar soundboardens ljudklipp. Flera klipp kan spela samtidigt; ett tryck till stoppar
/// direkt (ingen uttoning). Trim och volym (−12 … +6 dB) tillämpas vid uppspelning.
/// Ljudet blandas med annat ljud (t.ex. Spotify), som inte sänks.
@MainActor
@Observable
final class SoundEngine {
    /// Hur långt varje spelande klipp har kommit (0–1), för förloppsranden.
    private(set) var progress: [UUID: Double] = [:]

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var voices: [UUID: Voice] = [:]
    @ObservationIgnored private var timer: Timer?

    private struct Voice {
        let node: AVAudioPlayerNode
        let eq: AVAudioUnitEQ
        let start: Date
        let duration: Double
    }

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func isPlaying(_ clip: SoundClip) -> Bool {
        voices[clip.id] != nil
    }

    func toggle(_ clip: SoundClip) {
        if isPlaying(clip) { stop(clip.id) } else { play(clip) }
    }

    func play(_ clip: SoundClip) {
        stop(clip.id)
        guard let file = try? AVAudioFile(forReading: clip.fileURL) else { return }
        let rate = file.processingFormat.sampleRate
        let total = Double(file.length) / rate
        let start = min(max(0, clip.trimStart), total)
        let end = clip.trimEnd > start ? min(clip.trimEnd, total) : total
        let frames = AVAudioFrameCount(max(0, (end - start) * rate))
        guard frames > 0 else { return }

        let node = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 0)
        eq.globalGain = Float(min(max(clip.volumeDB, -12), 6))
        engine.attach(node)
        engine.attach(eq)
        engine.connect(node, to: eq, format: file.processingFormat)
        engine.connect(eq, to: engine.mainMixerNode, format: file.processingFormat)
        if !engine.isRunning { try? engine.start() }

        let id = clip.id
        node.scheduleSegment(file, startingFrame: AVAudioFramePosition(start * rate), frameCount: frames, at: nil) { [weak self] in
            Task { @MainActor in self?.finished(id, node: node) }
        }
        node.play()
        voices[id] = Voice(node: node, eq: eq, start: Date(), duration: end - start)
        progress[id] = 0
        startTimer()
    }

    func stop(_ id: UUID) {
        guard let voice = voices.removeValue(forKey: id) else { return }
        voice.node.stop()
        engine.detach(voice.node)
        engine.detach(voice.eq)
        progress[id] = nil
    }

    func stopAll() {
        for id in Array(voices.keys) { stop(id) }
    }

    private func finished(_ id: UUID, node: AVAudioPlayerNode) {
        // Bara om det är samma uppspelning (inte en som redan startats om).
        if voices[id]?.node === node { stop(id) }
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard !voices.isEmpty else {
            timer?.invalidate()
            timer = nil
            return
        }
        for (id, voice) in voices {
            progress[id] = min(1, Date().timeIntervalSince(voice.start) / max(voice.duration, 0.01))
        }
    }

    /// Vågform för trimningen: toppvärden i `count` delar av filen.
    nonisolated static func waveform(of url: URL, count: Int = 160) -> (peaks: [Float], duration: Double) {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(min(file.length, 44_100 * 600))),
              (try? file.read(into: buffer)) != nil,
              let channel = buffer.floatChannelData?[0] else { return ([], 0) }
        let frames = Int(buffer.frameLength)
        let step = max(1, frames / count)
        var peaks: [Float] = []
        var index = 0
        while index < frames {
            var peak: Float = 0
            for frame in index..<min(index + step, frames) { peak = max(peak, abs(channel[frame])) }
            peaks.append(peak)
            index += step
        }
        let maxPeak = peaks.max() ?? 1
        return (peaks.map { $0 / max(maxPeak, 0.0001) }, Double(file.length) / file.processingFormat.sampleRate)
    }
}
