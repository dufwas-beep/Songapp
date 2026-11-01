import AVFoundation

/// Lyckohjulets klack: pilens plastflik som slår mot en pinne. Ljudet räknas fram i
/// appen (ett kort smatter med en ton som klingar av), och flera klick kan ljuda
/// samtidigt när hjulet går fort. Tonhöjden varierar lite så att det låter levande.
final class WheelClickSound {
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var pitches: [AVAudioUnitVarispeed] = []
    private var next = 0
    private let buffer: AVAudioPCMBuffer?

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        buffer = Self.makeClick(format: format)
        for _ in 0..<6 {
            let player = AVAudioPlayerNode()
            let pitch = AVAudioUnitVarispeed()
            engine.attach(player)
            engine.attach(pitch)
            engine.connect(player, to: pitch, format: format)
            engine.connect(pitch, to: engine.mainMixerNode, format: format)
            players.append(player)
            pitches.append(pitch)
        }
        // Spelar tillsammans med annat ljud (Spotify, soundboarden).
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord {
            try? session.setCategory(.playback, options: [.mixWithOthers])
        }
        try? session.setActive(true)
        try? engine.start()
        for player in players { player.play() }
    }

    /// `speed`: hur fort hjulet går (0–1). Snabbt = lite högre och tystare klick.
    func click(speed: Double) {
        guard let buffer else { return }
        if !engine.isRunning {
            try? engine.start()
            for player in players { player.play() }
        }
        let player = players[next]
        pitches[next].rate = Float(0.9 + 0.25 * speed + Double.random(in: -0.05...0.05))
        next = (next + 1) % players.count
        player.volume = Float(1.0 - 0.35 * speed)
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    func stop() {
        engine.stop()
    }

    /// Ett klack: ett kort brus (anslaget) plus två toner som klingar av snabbt (fliken
    /// och hjulets trä).
    private static func makeClick(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let length = AVAudioFrameCount(rate * 0.06)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: length),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = length
        var seed: UInt32 = 12345
        for index in 0..<Int(length) {
            let t = Double(index) / rate
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Double(seed >> 8) / Double(1 << 24) * 2 - 1
            let snap = noise * exp(-t / 0.0018) * 0.7
            let flap = sin(2 * .pi * 2_300 * t) * exp(-t / 0.005) * 0.45
            let wood = sin(2 * .pi * 520 * t) * exp(-t / 0.014) * 0.5
            samples[index] = Float((snap + flap + wood) * 0.8)
        }
        return buffer
    }
}
