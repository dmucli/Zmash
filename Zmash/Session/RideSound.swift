import AVFoundation
import Synchronization
import ZmashKit

/// The ride's sounds, synthesised live (no recordings): wind and a crowd from filtered noise, freewheel ticking,
/// and short one-shots: a chain click, a summit bell, a kilometre chime, count-in beeps and a finish (D98).
/// Mixed under whatever else is playing.
@MainActor
final class RideSound {
    private let engine = AVAudioEngine()
    private let synth = Synth()
    private var node: AVAudioSourceNode?

    init(volume: Double) {
        synth.params.withLock { $0.volume = volume }
    }

    func start() {
        // Play under music or video instead of stopping it. (Playback, not ambient: the floating window needs it.)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let format = engine.outputNode.inputFormat(forBus: 0)
        let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)!
        let node = Self.sourceNode(synth: synth, format: mono)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: mono)
        self.node = node
        try? engine.start()
    }

    /// Built outside the main actor: the render block runs on the audio thread, and a closure made in a main-actor
    /// method would be main-actor isolated (and trap there).
    nonisolated private static func sourceNode(synth: Synth, format: AVAudioFormat) -> AVAudioSourceNode {
        let rate = format.sampleRate
        return AVAudioSourceNode(format: format) { @Sendable _, _, frames, buffers -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(buffers)
            guard let data = list.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            synth.render(into: data, frames: Int(frames), sampleRate: rate)
            return noErr
        }
    }

    func stop() {
        engine.stop()
        if let node { engine.detach(node) }
        node = nil
    }

    func apply(_ out: SoundCues.Output) {
        synth.params.withLock { p in
            p.wind = out.wind
            p.crowd = out.crowd
            p.freewheelRate = out.freewheelRate
            p.pending += out.oneShots
        }
    }
}

/// The synthesiser. Parameters come in under a lock; everything else lives on the audio thread.
private final class Synth: @unchecked Sendable {
    struct Params {
        var volume = 0.7
        var wind = 0.0
        var crowd = 0.0
        var freewheelRate = 0.0
        var pending: [SoundCues.OneShot] = []
    }

    let params = Mutex(Params())

    private struct Voice {
        var shot: SoundCues.OneShot
        var t = 0.0
    }

    // Audio-thread state.
    private var voices: [Voice] = []
    private var seed: UInt32 = 0x1234_5678
    private var wind = 0.0, crowd = 0.0
    private var windLP = 0.0, crowdLo = 0.0, crowdHi = 0.0, crowdAM = 0.5, crowdAMTarget = 0.5
    private var clickPhase = 0.0, clickEnv = 0.0, clickHP = 0.0, clickLast = 0.0

    private func noise() -> Double {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return Double(seed) / Double(UInt32.max) * 2 - 1
    }

    func render(into out: UnsafeMutablePointer<Float>, frames: Int, sampleRate sr: Double) {
        let p = params.withLock { p -> Params in
            let copy = p
            p.pending.removeAll()
            return copy
        }
        voices += p.pending.map { Voice(shot: $0) }
        let dt = 1 / sr
        let smooth = 1 - exp(-dt / 0.4)
        let windCut = 1 - exp(-2 * .pi * 500 * dt)
        let lo = 1 - exp(-2 * .pi * 350 * dt), hi = 1 - exp(-2 * .pi * 1800 * dt)
        let clickDecay = exp(-dt / 0.004)
        for n in 0..<frames {
            let white = noise()
            wind += (p.wind - wind) * smooth
            crowd += (p.crowd - crowd) * smooth
            // Wind: low rumble, louder with speed.
            windLP += (white - windLP) * windCut
            var s = windLP * wind * 0.9
            // Crowd: a band of noise that swells and ebbs, like voices.
            if crowd > 0.001 {
                crowdLo += (white - crowdLo) * lo
                crowdHi += (white - crowdHi) * hi
                if n % 512 == 0 { crowdAMTarget = 0.35 + 0.65 * (noise() * 0.5 + 0.5) }
                crowdAM += (crowdAMTarget - crowdAM) * 0.0008
                s += (crowdHi - crowdLo) * crowd * crowdAM * 1.2
            }
            // Freewheel: a short, bright click per pawl.
            if p.freewheelRate > 0 {
                clickPhase += p.freewheelRate * dt
                if clickPhase >= 1 { clickPhase -= 1; clickEnv = 1 }
            }
            if clickEnv > 0.001 {
                let hp = white - clickLast
                clickLast = white
                clickHP = hp
                s += clickHP * clickEnv * 0.12
                clickEnv *= clickDecay
            }
            s += voiceSample()
            out[n] = Float(max(-1, min(1, s * p.volume)))
            advanceVoices(dt)
        }
        voices.removeAll { $0.t > Self.length($0.shot) }
    }

    private static func length(_ shot: SoundCues.OneShot) -> Double {
        switch shot {
        case .shift: 0.08
        case .kilometre: 1.2
        case .summit: 3
        case .countIn: 2.3
        case .finish: 1.6
        }
    }

    private func advanceVoices(_ dt: Double) {
        for i in voices.indices { voices[i].t += dt }
    }

    private func tone(_ f: Double, _ t: Double, decay: Double) -> Double {
        guard t >= 0 else { return 0 }
        let attack = min(t / 0.004, 1)
        return sin(2 * .pi * f * t) * exp(-t / decay) * attack
    }

    private func voiceSample() -> Double {
        var s = 0.0
        for v in voices {
            let t = v.t
            switch v.shot {
            case .shift(let heavy):
                // Chain: a noise tick and a metallic ping, lower and longer on a big jump.
                let env = exp(-t / (heavy ? 0.014 : 0.007))
                s += noise() * env * 0.25 + tone(heavy ? 1500 : 2300, t, decay: heavy ? 0.03 : 0.02) * 0.12
            case .kilometre:
                s += tone(1318.5, t, decay: 0.35) * 0.1 + tone(2637, t, decay: 0.2) * 0.03
            case .summit:
                // A bell: inharmonic partials, the high ones dying first.
                let partials: [(Double, Double, Double)] = [(1, 1, 1.6), (2.76, 0.5, 1.0), (5.4, 0.25, 0.6), (8.93, 0.12, 0.4)]
                for (ratio, gain, decay) in partials { s += tone(660 * ratio, t, decay: decay) * gain * 0.14 }
            case .countIn:
                for start in [0.0, 1.0, 2.0] where t >= start && t < start + 0.12 {
                    s += sin(2 * .pi * 880 * (t - start)) * 0.12
                }
            case .finish:
                for (k, f) in [523.25, 659.25, 783.99].enumerated() { s += tone(f, t - Double(k) * 0.15, decay: 0.5) * 0.1 }
            }
        }
        return s
    }
}
