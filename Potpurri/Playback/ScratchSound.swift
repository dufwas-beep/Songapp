import AVFoundation
import Foundation

/// Ljudet när man scratchar LP:n på välkomstsidan: en kort "inspelning" (en sjungande ton
/// med knaster) som spelas framåt och bakåt i samma takt som skivan dras – som en riktig
/// skiva. Står skivan still är det tyst.
final class ScratchSound: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private let samples: [Float]
    private let lock = NSLock()
    /// Önskad hastighet: 1 = vanlig fart framåt, −1 = bakåt, 0 = stilla.
    private var targetRate: Double = 0
    // Används bara i ljudtråden.
    private var rate: Double = 0
    private var position: Double = 0
    private var lastIn: Float = 0
    private var lastOut: Float = 0

    init() {
        let sampleRate = 44_100.0
        samples = Self.makeRecording(sampleRate: sampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        let node = AVAudioSourceNode(format: format) { [unowned self] _, _, frameCount, bufferList in
            self.render(frameCount: Int(frameCount), into: UnsafeMutableAudioBufferListPointer(bufferList))
            return noErr
        }
        self.node = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    func start() {
        guard !engine.isRunning else { return }
        try? engine.start()
    }

    func stop() {
        setRate(0)
        engine.stop()
    }

    func setRate(_ value: Double) {
        lock.withLock { targetRate = min(max(value, -5), 5) }
    }

    private func render(frameCount: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        let target = lock.withLock { targetRate }
        let count = Double(samples.count)
        for frame in 0..<frameCount {
            // Mjuk ändring av farten, annars knäpper det.
            rate += (target - rate) * 0.004
            position += rate
            if position < 0 { position += count } else if position >= count { position -= count }
            let index = Int(position)
            let fraction = Float(position - Double(index))
            let a = samples[index]
            let b = samples[(index + 1) % samples.count]
            let x = a + (b - a) * fraction
            // Tar bort likström: en skiva som står still låter inte.
            let y = x - lastIn + 0.995 * lastOut
            lastIn = x
            lastOut = y
            for buffer in buffers {
                buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = y * 0.7
            }
        }
    }

    /// Tre sekunder "sång": stavelser med glidande tonhöjd, lite brus och knaster.
    private static func makeRecording(sampleRate: Double) -> [Float] {
        let count = Int(sampleRate * 3)
        var result = [Float](repeating: 0, count: count)
        var phase = 0.0
        var smooth: Float = 0
        var seed: UInt32 = 2024
        func noise() -> Float {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Float(seed >> 8) / Float(1 << 24) * 2 - 1
        }
        for n in 0..<count {
            let t = Double(n) / sampleRate
            let syllable = t.truncatingRemainder(dividingBy: 0.42) / 0.42
            let envelope = Float(pow(sin(.pi * min(1, syllable * 1.25)), 0.6))
            let pitch = 130 + 110 * (1 - syllable) + 12 * sin(2 * .pi * 5.5 * t)
            phase += pitch / sampleRate
            let saw = Float(2 * (phase - floor(phase)) - 1)
            // Mjukare klang (enkelt lågpassfilter) – låter mer som en röst.
            smooth += (saw - smooth) * 0.18
            let crackle: Float = noise() > 0.9993 ? noise() * 0.8 : 0
            result[n] = smooth * envelope * 0.9 + noise() * 0.04 * envelope + crackle
        }
        return result
    }
}
