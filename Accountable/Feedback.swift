import UIKit
import CoreHaptics
import AVFoundation

// MARK: - Haptics

/// Every tap in the app goes through here. Quick taps use UIKit's feedback generators;
/// celebrations use Core Haptics patterns for longer, richer effects.
final class Haptics {
    static let shared = Haptics()

    enum Kind { case tick, light, medium, heavy, rigid, soft, success, warning, error, none }

    var enabled: Bool { UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true }

    private var engine: CHHapticEngine?
    private let selection = UISelectionFeedbackGenerator()
    private let notify = UINotificationFeedbackGenerator()
    private var impacts: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

    private init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
        engine?.playsHapticsOnly = true
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
    }

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, _ intensity: CGFloat = 1) {
        let g = impacts[style] ?? UIImpactFeedbackGenerator(style: style)
        impacts[style] = g
        g.impactOccurred(intensity: intensity)
    }

    func play(_ kind: Kind) {
        guard enabled else { return }
        switch kind {
        case .tick: selection.selectionChanged()
        case .light: impact(.light)
        case .medium: impact(.medium)
        case .heavy: impact(.heavy)
        case .rigid: impact(.rigid)
        case .soft: impact(.soft)
        case .success: notify.notificationOccurred(.success)
        case .warning: notify.notificationOccurred(.warning)
        case .error: notify.notificationOccurred(.error)
        case .none: break
        }
    }

    private func run(_ events: [CHHapticEvent], fallback: Kind) {
        guard enabled else { return }
        guard let engine else { play(fallback); return }
        do {
            try engine.start()
            let pattern = try CHHapticPattern(events: events, parameters: [])
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            play(fallback)
        }
    }

    private func tap(_ time: Double, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
        ], relativeTime: time)
    }

    private func buzz(_ time: Double, _ duration: Double, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
        ], relativeTime: time, duration: duration)
    }

    /// Rising taps that end in a rumble: level ups, chests, streaks.
    func fanfare(steps: Int = 6) {
        var events: [CHHapticEvent] = []
        for i in 0..<steps {
            let v = Float(0.35 + 0.65 * Double(i) / Double(max(1, steps - 1)))
            events.append(tap(Double(i) * 0.075, v, 0.55))
        }
        events.append(buzz(Double(steps) * 0.075 + 0.04, 0.38, 1, 0.25))
        run(events, fallback: .success)
    }

    /// Two quick thumps for a combo.
    func combo() {
        run([tap(0, 0.8, 0.8), tap(0.09, 1, 0.9)], fallback: .heavy)
    }

    /// A slow double beat for losing a heart.
    func heartbreak() {
        run([tap(0, 1, 0.2), tap(0.16, 0.7, 0.2), buzz(0.34, 0.25, 0.5, 0.1)], fallback: .error)
    }

    /// A shimmer of tiny taps for gems and loot.
    func sparkle(count: Int = 8) {
        var events: [CHHapticEvent] = []
        for i in 0..<count {
            events.append(tap(Double(i) * 0.045, Float(0.3 + Double(i % 3) * 0.2), 1))
        }
        run(events, fallback: .success)
    }

    /// Countdown to a session finishing.
    func countdown() {
        run([tap(0, 0.6, 0.5), tap(0.5, 0.75, 0.6), tap(1.0, 1, 0.8), buzz(1.15, 0.5, 1, 0.4)], fallback: .success)
    }
}

// MARK: - Sound

/// Tiny synthesizer: every sound is generated in code, so the app ships no audio files.
/// Uses the ambient category, so it respects the silent switch and mixes with music.
final class SoundFX {
    static let shared = SoundFX()

    enum Effect {
        case tap, pop, xp, combo(Int), complete, chest, levelUp, streak, heartLost, quest, start, purchase, error, loot(Int)

        var key: String {
            switch self {
            case .tap: return "tap"
            case .pop: return "pop"
            case .xp: return "xp"
            case .combo(let n): return "combo\(min(n, 10))"
            case .complete: return "complete"
            case .chest: return "chest"
            case .levelUp: return "level"
            case .streak: return "streak"
            case .heartLost: return "heart"
            case .quest: return "quest"
            case .start: return "start"
            case .purchase: return "purchase"
            case .error: return "error"
            case .loot(let r): return "loot\(r)"
            }
        }
    }

    var enabled: Bool { UserDefaults.standard.object(forKey: "sound") as? Bool ?? true }

    private struct Note {
        var f: Double
        var t: Double
        var d: Double
        var wave = 0
        var v = 0.22
        var slide: Double? = nil
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var cache: [String: AVAudioPCMBuffer] = [:]

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        for _ in 0..<5 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
    }

    private func ensureRunning() -> Bool {
        if engine.isRunning { return true }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    func play(_ effect: Effect) {
        guard enabled else { return }
        let key = effect.key
        let buffer: AVAudioPCMBuffer
        if let cached = cache[key] {
            buffer = cached
        } else {
            guard let made = render(notes(for: effect)) else { return }
            cache[key] = made
            buffer = made
        }
        guard ensureRunning() else { return }
        let p = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        p.stop()
        p.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        p.play()
    }

    private func notes(for effect: Effect) -> [Note] {
        switch effect {
        case .tap:
            return [Note(f: 760, t: 0, d: 0.05, wave: 0, v: 0.12, slide: 1150)]
        case .pop:
            return [Note(f: 520, t: 0, d: 0.09, wave: 1, v: 0.2, slide: 1040)]
        case .xp:
            return [Note(f: 988, t: 0, d: 0.1, wave: 1, v: 0.18), Note(f: 1480, t: 0.07, d: 0.18, wave: 1, v: 0.16)]
        case .combo(let n):
            let base = 523.25 * pow(2, Double(min(n, 10)) / 12)
            return [1, 1.26, 1.5, 2].enumerated().map { i, m in
                Note(f: base * m, t: Double(i) * 0.06, d: 0.2, wave: 1, v: 0.17)
            }
        case .complete:
            return [
                Note(f: 523, t: 0, d: 0.16, wave: 1), Note(f: 659, t: 0.11, d: 0.16, wave: 1),
                Note(f: 784, t: 0.22, d: 0.16, wave: 1), Note(f: 1047, t: 0.33, d: 0.5, wave: 1, v: 0.24),
                Note(f: 659, t: 0.33, d: 0.5, wave: 0, v: 0.12), Note(f: 784, t: 0.33, d: 0.5, wave: 0, v: 0.12)
            ]
        case .chest:
            return [
                Note(f: 392, t: 0, d: 0.25, wave: 2, v: 0.08, slide: 784),
                Note(f: 1047, t: 0.2, d: 0.14, wave: 1), Note(f: 1319, t: 0.27, d: 0.14, wave: 1),
                Note(f: 1568, t: 0.34, d: 0.14, wave: 1), Note(f: 2093, t: 0.41, d: 0.4, wave: 0, v: 0.18)
            ]
        case .levelUp:
            let fs: [Double] = [523, 659, 784, 1047, 1319, 1568]
            var out = fs.enumerated().map { i, f in Note(f: f, t: Double(i) * 0.09, d: i == 5 ? 0.8 : 0.2, wave: 1, v: 0.2) }
            out.append(Note(f: 262, t: 0, d: 0.9, wave: 0, v: 0.14))
            return out
        case .streak:
            return [
                Note(f: 180, t: 0, d: 0.35, wave: 2, v: 0.07, slide: 900),
                Note(f: 1047, t: 0.3, d: 0.18, wave: 1), Note(f: 1568, t: 0.4, d: 0.5, wave: 1, v: 0.2)
            ]
        case .heartLost:
            return [Note(f: 440, t: 0, d: 0.3, wave: 0, v: 0.22, slide: 220), Note(f: 196, t: 0.28, d: 0.4, wave: 1, v: 0.18)]
        case .quest:
            return [Note(f: 784, t: 0, d: 0.12, wave: 1), Note(f: 988, t: 0.09, d: 0.12, wave: 1), Note(f: 1319, t: 0.18, d: 0.35, wave: 1, v: 0.2)]
        case .start:
            return [Note(f: 330, t: 0, d: 0.25, wave: 1, v: 0.16, slide: 990), Note(f: 1320, t: 0.22, d: 0.3, wave: 0, v: 0.15)]
        case .purchase:
            return [Note(f: 1319, t: 0, d: 0.08, wave: 0), Note(f: 1760, t: 0.06, d: 0.08, wave: 0), Note(f: 2637, t: 0.12, d: 0.3, wave: 0, v: 0.16)]
        case .error:
            return [Note(f: 220, t: 0, d: 0.12, wave: 2, v: 0.1), Note(f: 185, t: 0.13, d: 0.18, wave: 2, v: 0.1)]
        case .loot(let r):
            let lift = 1 + Double(r) * 0.07
            var out = [784.0, 988, 1175, 1568].enumerated().map { i, f in Note(f: f * lift, t: Double(i) * 0.07, d: 0.3, wave: 1, v: 0.18) }
            if r >= 2 {
                out += [2093.0, 2637, 3136].enumerated().map { i, f in Note(f: f, t: 0.35 + Double(i) * 0.08, d: 0.35, wave: 0, v: 0.1) }
            }
            return out
        }
    }

    private func render(_ notes: [Note]) -> AVAudioPCMBuffer? {
        let sr = 44_100.0
        let total = (notes.map { $0.t + $0.d }.max() ?? 0) + 0.05
        let frames = AVAudioFrameCount(total * sr)
        guard frames > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let ch = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = frames
        let count = Int(frames)
        for i in 0..<count { ch[i] = 0 }
        for n in notes {
            let start = Int(n.t * sr)
            let len = Int(n.d * sr)
            var phase = 0.0
            for i in 0..<len {
                let idx = start + i
                if idx >= count { break }
                let p = Double(i) / Double(len)
                let f: Double
                if let s = n.slide { f = n.f * pow(s / n.f, p) } else { f = n.f }
                phase += f / sr
                let x = phase - floor(phase)
                let y: Double
                switch n.wave {
                case 1: y = x < 0.5 ? 4 * x - 1 : 3 - 4 * x
                case 2: y = x < 0.5 ? 0.6 : -0.6
                default: y = sin(2 * Double.pi * x)
                }
                let attack = min(1, Double(i) / (0.005 * sr))
                let env = attack * pow(1 - p, 2)
                ch[idx] += Float(y * env * n.v)
            }
        }
        for i in 0..<count { ch[i] = max(-0.95, min(0.95, ch[i])) }
        return buf
    }
}
