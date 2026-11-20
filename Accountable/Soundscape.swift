import AVFoundation
import SwiftUI
import Observation

/// Background sound for focusing, generated live (no audio files).
/// Ten layers mix at their own volumes under one master volume, glide instead of jumping, keep playing with
/// the screen off, and pick themselves back up after a phone call or when headphones are plugged in or out.
@Observable
final class Soundscape {
    static let shared = Soundscape()

    struct LayerInfo: Identifiable {
        let id: String
        let name: String
        let icon: String
    }

    static let layers: [LayerInfo] = [
        LayerInfo(id: "rain", name: "Rain", icon: "cloud.rain.fill"),
        LayerInfo(id: "storm", name: "Thunder", icon: "cloud.bolt.fill"),
        LayerInfo(id: "waves", name: "Waves", icon: "water.waves"),
        LayerInfo(id: "wind", name: "Wind", icon: "wind"),
        LayerInfo(id: "forest", name: "Birds", icon: "bird.fill"),
        LayerInfo(id: "night", name: "Crickets", icon: "moon.stars.fill"),
        LayerInfo(id: "fire", name: "Fire", icon: "flame.fill"),
        LayerInfo(id: "cafe", name: "Café", icon: "cup.and.saucer.fill"),
        LayerInfo(id: "brown", name: "Brown noise", icon: "waveform"),
        LayerInfo(id: "drone", name: "Deep hum", icon: "circle.hexagongrid.fill")
    ]

    /// One-tap mixes, so nobody has to build a soundscape from scratch.
    struct Preset: Identifiable {
        let id: String
        let name: String
        let icon: String
        let levels: [String: Double]
    }

    static let presets: [Preset] = [
        Preset(id: "rainycafe", name: "Rainy café", icon: "cup.and.saucer.fill", levels: ["rain": 0.55, "cafe": 0.45]),
        Preset(id: "deep", name: "Deep focus", icon: "brain.head.profile", levels: ["brown": 0.5, "drone": 0.35]),
        Preset(id: "storm", name: "Storm", icon: "cloud.bolt.rain.fill", levels: ["rain": 0.65, "storm": 0.6, "wind": 0.2]),
        Preset(id: "camp", name: "Campfire", icon: "tent.fill", levels: ["fire": 0.65, "night": 0.35, "wind": 0.15]),
        Preset(id: "ocean", name: "Ocean", icon: "water.waves", levels: ["waves": 0.7, "wind": 0.25]),
        Preset(id: "forest", name: "Forest", icon: "tree.fill", levels: ["forest": 0.55, "wind": 0.3, "rain": 0.1])
    ]

    private(set) var isPlaying = false

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var voices: [String: Voice] = [:]
    @ObservationIgnored private var built = false
    @ObservationIgnored private var stopWork: DispatchWorkItem?
    @ObservationIgnored private var lastLevels: [String: Double] = [:]
    @ObservationIgnored private var master: Float = 0.8

    private init() {
        let nc = NotificationCenter.default
        // A call or Siri pauses audio; resume the mix when the interruption ends.
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, self.isPlaying,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            self.restart()
        }
        // Headphones in or out rebuild the output; start again so the sound doesn't silently stop.
        nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.isPlaying else { return }
            self.restart()
        }
    }

    /// Sets each layer's volume (0...1). Changes glide rather than jump.
    func apply(_ levels: [String: Double]) {
        lastLevels = levels
        for l in Soundscape.layers {
            voices[l.id]?.target = Float(max(0, min(1, levels[l.id] ?? 0)))
        }
    }

    /// Overall volume for the whole mix (0...1).
    func setMaster(_ value: Double) {
        master = Float(max(0, min(1, value)))
        engine.mainMixerNode.outputVolume = master
    }

    func play(_ levels: [String: Double], master: Double? = nil) {
        stopWork?.cancel()
        build()
        if let master { setMaster(master) }
        guard startEngine() else { return }
        apply(levels)
        isPlaying = true
    }

    /// Fades out over about a second, then releases the audio session.
    func stop() {
        guard isPlaying else { return }
        for v in voices.values { v.target = 0 }
        isPlaying = false
        let w = DispatchWorkItem { [weak self] in
            guard let self, !self.isPlaying else { return }
            self.engine.pause()
            let s = AVAudioSession.sharedInstance()
            try? s.setActive(false, options: .notifyOthersOnDeactivation)
            try? s.setCategory(.ambient, options: [.mixWithOthers])
        }
        stopWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: w)
    }

    @discardableResult
    private func startEngine() -> Bool {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try s.setActive(true)
            if !engine.isRunning { try engine.start() }
            return true
        } catch {
            return false
        }
    }

    private func restart() {
        engine.stop()
        if startEngine() { apply(lastLevels) }
    }

    private func build() {
        guard !built else { return }
        built = true
        let out = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let rate = out > 0 ? out : 48_000
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        for l in Soundscape.layers {
            let v = Voice(kind: l.id, sampleRate: Float(rate))
            voices[l.id] = v
            let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
                v.render(frames: Int(frameCount), into: UnsafeMutableAudioBufferListPointer(bufferList))
                return noErr
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
        engine.mainMixerNode.outputVolume = master
        engine.prepare()
    }
}

/// Per-ear filter state. A plain struct, so the audio thread never allocates.
private struct Chan {
    var b: Float = 0
    var p0: Float = 0, p1: Float = 0, p2: Float = 0, p3: Float = 0, p4: Float = 0, p5: Float = 0, p6: Float = 0
    var lp: Float = 0
    var lp2: Float = 0
    var hp: Float = 0
    var dropEnv: Float = 0
    var dropTone: Float = 0
    var dropPhase: Float = 0
    var dropFreq: Float = 0
}

/// One generated sound. Runs on the audio thread, so it only touches its own state and never allocates.
private final class Voice {
    let kind: String
    let sr: Float
    var target: Float = 0
    private var gain: Float = 0

    private var seed: UInt32 = UInt32.random(in: 1...UInt32.max)
    private var t: Float = 0
    private var L = Chan()
    private var R = Chan()

    // Café
    private var clinkEnv: Float = 0
    private var clinkPhase: Float = 0
    private var clinkFreq: Float = 3000
    private var clinkPan: Float = 0.5

    // Fire
    private var crackle: Float = 0
    private var crackPan: Float = 0.5
    private var hissEnv: Float = 0

    // Waves
    private var wavePeriod: Float = 9
    private var wavePhase: Float = 0

    // Thunder
    private var rumbleEnv: Float = 0
    private var rumbleAttack: Float = 0
    private var rumbleWait: Float = 6

    // Wind
    private var gust: Float = 0.4
    private var gustTarget: Float = 0.4
    private var gustWait: Float = 2

    // Birds
    private var birdEnv: Float = 0
    private var birdPhase: Float = 0
    private var birdFreq: Float = 3000
    private var birdSweep: Float = 0
    private var birdNotes = 0
    private var birdGap: Float = 0
    private var birdWait: Float = 1.5
    private var birdPan: Float = 0.5
    private var birdBase: Float = 3000

    // Crickets
    private var crickPhase: Float = 0
    private var crickClock: Float = 0
    private var crickRate: Float = 0.9
    private var crick2Clock: Float = 0.37

    // Deep hum
    private var hum: (Float, Float, Float, Float) = (0, 0, 0, 0)
    private var humR: (Float, Float, Float, Float) = (0, 0, 0, 0)

    init(kind: String, sampleRate: Float) {
        self.kind = kind
        self.sr = sampleRate
        wavePeriod = Float.random(in: 7...11)
        rumbleWait = Float.random(in: 4...10)
    }

    @inline(__always) private func white() -> Float {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return Float(seed) / Float(UInt32.max) * 2 - 1
    }

    @inline(__always) private func rand01() -> Float { (white() + 1) * 0.5 }

    @inline(__always) private func pinkNoise(_ c: inout Chan) -> Float {
        let w = white()
        c.p0 = 0.99886 * c.p0 + w * 0.0555179
        c.p1 = 0.99332 * c.p1 + w * 0.0750759
        c.p2 = 0.96900 * c.p2 + w * 0.1538520
        c.p3 = 0.86650 * c.p3 + w * 0.3104856
        c.p4 = 0.55000 * c.p4 + w * 0.5329522
        c.p5 = -0.7616 * c.p5 - w * 0.0168980
        let out = c.p0 + c.p1 + c.p2 + c.p3 + c.p4 + c.p5 + c.p6 + w * 0.5362
        c.p6 = w * 0.115926
        return out * 0.11
    }

    @inline(__always) private func brownNoise(_ c: inout Chan) -> Float {
        c.b = (c.b + 0.02 * white()) / 1.02
        return c.b * 3.5
    }

    func render(frames: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        guard buffers.count > 0, let left = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
        let dt = 1 / sr
        for i in 0..<frames {
            gain += (target - gain) * 0.00012
            var l: Float = 0, r: Float = 0
            if gain > 0.0005 {
                switch kind {
                case "rain": l = rain(&L); r = rain(&R)
                case "storm": (l, r) = storm(dt)
                case "cafe": (l, r) = cafe()
                case "brown": l = brownNoise(&L) * 0.9; r = brownNoise(&R) * 0.9
                case "waves": (l, r) = waves(dt)
                case "fire": (l, r) = fire()
                case "wind": (l, r) = wind(dt)
                case "forest": (l, r) = birds(dt)
                case "night": (l, r) = crickets(dt)
                case "drone": (l, r) = drone()
                default: break
                }
            }
            t += dt
            if t > 3600 { t -= 3600 }
            left[i] = tanhf(l * gain)
            right?[i] = tanhf(r * gain)
        }
    }

    // Soft hiss, a low body, and individual drops that ring briefly at their own pitch, different in each ear.
    private func rain(_ c: inout Chan) -> Float {
        let p = pinkNoise(&c)
        c.lp += (p - c.lp) * 0.05
        let hiss = (p - c.lp) * 0.5
        if rand01() < 42 / sr {
            c.dropEnv = 0.25 + 0.75 * rand01()
            c.dropFreq = 900 + 2600 * rand01()
        }
        c.dropEnv *= 0.9955
        c.dropPhase += 2 * .pi * c.dropFreq / sr
        if c.dropPhase > 2 * .pi { c.dropPhase -= 2 * .pi }
        c.dropTone += (white() - c.dropTone) * 0.35
        let drop = (c.dropTone * 0.7 + sinf(c.dropPhase) * 0.3) * c.dropEnv * 0.32
        return hiss + drop + brownNoise(&c) * 0.1
    }

    // Distant thunder: long, low rolls that build slowly and fade over many seconds, every so often.
    private func storm(_ dt: Float) -> (Float, Float) {
        rumbleWait -= dt
        if rumbleWait <= 0 {
            rumbleAttack = 0.5 + 0.5 * rand01()
            rumbleWait = 14 + 22 * rand01()
        }
        if rumbleAttack > 0 {
            rumbleEnv += (rumbleAttack - rumbleEnv) * 0.00008
            if rumbleEnv > rumbleAttack * 0.95 { rumbleAttack = 0 }
        } else {
            rumbleEnv *= 0.99994
        }
        // Rumble flickers a little so it sounds like rolling, not a steady hum.
        let flicker: Float = 0.75 + 0.25 * sinf(2 * .pi * 0.7 * t) * sinf(2 * .pi * 0.23 * t)
        func roll(_ c: inout Chan) -> Float {
            let b = brownNoise(&c)
            c.lp += (b - c.lp) * 0.012
            c.lp2 += (c.lp - c.lp2) * 0.05
            return c.lp2 * 5
        }
        let bed = brownNoise(&L) * 0.12
        let l = roll(&L) * rumbleEnv * flicker + bed
        let r = roll(&R) * rumbleEnv * flicker + bed
        return (l, r)
    }

    // A low murmur that rises and falls like conversation, with the odd cup or spoon somewhere in the room.
    private func cafe() -> (Float, Float) {
        let swell = 0.55 + 0.25 * sinf(2 * .pi * 0.13 * t) + 0.2 * sinf(2 * .pi * 0.31 * t + 1.3)
        func murmur(_ c: inout Chan) -> Float {
            let p = pinkNoise(&c)
            c.lp += (p - c.lp) * 0.08
            c.lp2 += (c.lp - c.lp2) * 0.01
            return (c.lp - c.lp2) * 1.6 * swell
        }
        var l = murmur(&L), r = murmur(&R)
        if clinkEnv < 0.001 && rand01() < 0.25 / sr {
            clinkEnv = 0.07 + 0.1 * rand01()
            clinkFreq = 2400 + 2200 * rand01()
            clinkPan = rand01()
        }
        if clinkEnv > 0.0005 {
            clinkPhase += 2 * .pi * clinkFreq / sr
            if clinkPhase > 2 * .pi { clinkPhase -= 2 * .pi }
            // Two partials: a cup rings with an inharmonic overtone.
            let s = (sinf(clinkPhase) + 0.4 * sinf(clinkPhase * 2.76)) * clinkEnv
            clinkEnv *= 0.99972
            l += s * (1 - clinkPan)
            r += s * clinkPan
        }
        return (l, r)
    }

    // Slow swells of low noise, with a brighter wash as each wave breaks and a fizz as it pulls back.
    private func waves(_ dt: Float) -> (Float, Float) {
        wavePhase += dt / wavePeriod
        if wavePhase >= 1 { wavePhase -= 1; wavePeriod = 7 + 4 * rand01() }
        let swell = 0.5 - 0.5 * cosf(2 * .pi * wavePhase)
        let crest = swell * swell * swell
        let fizz = max(0, sinf(2 * .pi * (wavePhase - 0.55))) * 0.35
        func wave(_ c: inout Chan) -> Float {
            let p = pinkNoise(&c)
            c.lp += (p - c.lp) * 0.12
            c.hp += (p - c.hp) * 0.4
            return brownNoise(&c) * (0.25 + 0.6 * swell) + c.lp * 1.2 * crest + (p - c.hp) * fizz
        }
        return (wave(&L), wave(&R))
    }

    // A warm rumble, crackles that land left or right, and the occasional hiss of sap.
    private func fire() -> (Float, Float) {
        if rand01() < 11 / sr { crackle = 0.3 + 0.7 * rand01(); crackPan = rand01() }
        crackle *= 0.985
        if hissEnv < 0.01 && rand01() < 0.05 / sr { hissEnv = 0.25 }
        hissEnv *= 0.99992
        let pop = white() * crackle * 0.9
        let hiss = white() * hissEnv * 0.15
        let bl = brownNoise(&L)
        let br = brownNoise(&R)
        L.lp += (bl - L.lp) * 0.03
        R.lp += (br - R.lp) * 0.03
        return (L.lp * 1.8 + pop * (1 - crackPan) + hiss, R.lp * 1.8 + pop * crackPan + hiss)
    }

    // Moving air: noise through a filter that opens and closes with slow, random gusts.
    private func wind(_ dt: Float) -> (Float, Float) {
        gustWait -= dt
        if gustWait <= 0 { gustTarget = 0.15 + 0.85 * rand01(); gustWait = 2 + 5 * rand01() }
        gust += (gustTarget - gust) * 0.00002
        let cutoff = 0.004 + 0.03 * gust
        let sway = 0.5 + 0.35 * sinf(2 * .pi * 0.05 * t)
        func air(_ c: inout Chan) -> Float {
            let p = pinkNoise(&c)
            c.lp += (p - c.lp) * cutoff
            c.lp2 += (c.lp - c.lp2) * cutoff
            return c.lp2 * (2.2 + 3 * gust)
        }
        return (air(&L) * (1.2 - sway * 0.4), air(&R) * (0.8 + sway * 0.4))
    }

    // Songbirds: short phrases of chirps that sweep up or down, each bird somewhere different in the space.
    private func birds(_ dt: Float) -> (Float, Float) {
        // A soft leafy bed underneath.
        let bedL = pinkNoise(&L), bedR = pinkNoise(&R)
        L.lp += (bedL - L.lp) * 0.02
        R.lp += (bedR - R.lp) * 0.02
        var l = L.lp * 0.5, r = R.lp * 0.5

        if birdNotes == 0 {
            birdWait -= dt
            if birdWait <= 0 {
                birdNotes = 2 + Int(rand01() * 5)
                birdBase = 2200 + 2600 * rand01()
                birdPan = rand01()
                birdWait = 0.8 + 3.5 * rand01()
                birdGap = 0
            }
        } else if birdEnv < 0.002 {
            birdGap -= dt
            if birdGap <= 0 {
                birdEnv = 0.6 + 0.4 * rand01()
                birdFreq = birdBase * (0.9 + 0.2 * rand01())
                birdSweep = (rand01() > 0.5 ? 1 : -1) * (3000 + 6000 * rand01())
                birdNotes -= 1
                birdGap = 0.05 + 0.12 * rand01()
            }
        }
        if birdEnv > 0.0005 {
            birdFreq = max(1200, min(8000, birdFreq + birdSweep * dt))
            birdPhase += 2 * .pi * birdFreq / sr
            if birdPhase > 2 * .pi { birdPhase -= 2 * .pi }
            let s = sinf(birdPhase) * birdEnv * 0.22
            birdEnv *= 0.9992
            l += s * (1 - birdPan)
            r += s * birdPan
        }
        return (l, r)
    }

    // A summer night: two crickets trilling out of step, one in each ear, over a hush.
    private func crickets(_ dt: Float) -> (Float, Float) {
        crickPhase += 2 * .pi * 4600 / sr
        if crickPhase > 2 * .pi { crickPhase -= 2 * .pi }
        let carrier = sinf(crickPhase)
        func chirp(_ clock: inout Float) -> Float {
            clock += dt
            if clock >= crickRate { clock -= crickRate }
            // Three quick pulses at the start of each cycle.
            guard clock < 0.12 else { return 0 }
            let pulse = sinf(.pi * (clock.truncatingRemainder(dividingBy: 0.04) / 0.04))
            return pulse * pulse
        }
        let a = chirp(&crickClock), b = chirp(&crick2Clock)
        let hushL = pinkNoise(&L), hushR = pinkNoise(&R)
        L.lp += (hushL - L.lp) * 0.01
        R.lp += (hushR - R.lp) * 0.01
        let l = carrier * (a * 0.16 + b * 0.05) + L.lp * 0.4
        let r = carrier * (a * 0.05 + b * 0.16) + R.lp * 0.4
        return (l, r)
    }

    // A warm open fifth that breathes slowly, slightly detuned between the ears so it feels wide.
    private func drone() -> (Float, Float) {
        let tau: Float = 2 * .pi
        hum.0 += tau * 110 / sr; hum.1 += tau * 164.81 / sr; hum.2 += tau * 220 / sr; hum.3 += tau * 329.63 / sr
        humR.0 += tau * 110.4 / sr; humR.1 += tau * 165.2 / sr; humR.2 += tau * 220.6 / sr; humR.3 += tau * 330.2 / sr
        if hum.0 > tau { hum.0 -= tau }; if hum.1 > tau { hum.1 -= tau }; if hum.2 > tau { hum.2 -= tau }; if hum.3 > tau { hum.3 -= tau }
        if humR.0 > tau { humR.0 -= tau }; if humR.1 > tau { humR.1 -= tau }; if humR.2 > tau { humR.2 -= tau }; if humR.3 > tau { humR.3 -= tau }
        let b1: Float = 0.6 + 0.4 * sinf(tau * 0.05 * t)
        let b2: Float = 0.5 + 0.5 * sinf(tau * 0.031 * t + 1)
        let l = sinf(hum.0) * 0.30 + sinf(hum.1) * 0.20 * b1 + sinf(hum.2) * 0.12 + sinf(hum.3) * 0.06 * b2
        let r = sinf(humR.0) * 0.30 + sinf(humR.1) * 0.20 * b2 + sinf(humR.2) * 0.12 + sinf(humR.3) * 0.06 * b1
        return (l, r)
    }
}

// MARK: - Mixer

/// Pick a mix with one tap, or tap a sound to turn it on and drag across it to set its volume.
struct SoundMixer: View {
    @Environment(AppStore.self) private var store
    var dark = true
    var livePreview = false

    var body: some View {
        @Bindable var store = store
        let theme = TimerTheme.find(store.data.theme)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SOUNDSCAPE").font(.caption.weight(.bold)).tracking(1.5)
                    .foregroundStyle(dark ? Palette.nightMuted : Color.secondary)
                Spacer()
                Toggle("Play during focus", isOn: $store.data.soundOn)
                    .labelsHidden()
                    .tint(theme.c1)
                    .onChange(of: store.data.soundOn) { _, on in
                        if livePreview { on ? play() : Soundscape.shared.stop() }
                    }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Soundscape.presets) { p in
                        let on = matches(p)
                        Button {
                            withAnimation(.calm) {
                                store.data.soundLevels = p.levels
                                store.data.soundOn = true
                            }
                            changed()
                        } label: {
                            Label(p.name, systemImage: p.icon)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(on ? Color.black : (dark ? Palette.nightInk : Color.primary))
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .background(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(dark ? Palette.nightChip : Palette.track), in: Capsule())
                                .overlay(Capsule().stroke(dark && !on ? Palette.nightLine : .clear, lineWidth: 1))
                        }
                        .buttonStyle(PressableStyle(haptic: .tick, scale: 0.94))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .scrollClipDisabled()

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Soundscape.layers) { l in
                    LayerSlider(layer: l, dark: dark, theme: theme, value: Binding(
                        get: { store.data.soundLevels[l.id] ?? 0 },
                        set: { v in
                            store.data.soundLevels[l.id] = v
                            if v > 0 && !store.data.soundOn { store.data.soundOn = true }
                            changed()
                        }))
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").font(.caption)
                Slider(value: Binding(
                    get: { store.data.soundMaster },
                    set: { v in
                        store.data.soundMaster = v
                        Soundscape.shared.setMaster(v)
                    }), in: 0...1)
                    .tint(theme.c1)
                Image(systemName: "speaker.wave.3.fill").font(.caption)
            }
            .foregroundStyle(dark ? Palette.nightMuted : Color.secondary)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Volume")
        }
        .opacity(store.data.soundOn ? 1 : 0.55)
        .animation(.calm, value: store.data.soundOn)
    }

    private func play() {
        Soundscape.shared.play(store.data.soundLevels, master: store.data.soundMaster)
    }

    private func changed() {
        if livePreview || Soundscape.shared.isPlaying {
            if !Soundscape.shared.isPlaying { play() }
            Soundscape.shared.apply(store.data.soundLevels)
        }
    }

    private func matches(_ p: Soundscape.Preset) -> Bool {
        Soundscape.layers.allSatisfy { l in
            abs((store.data.soundLevels[l.id] ?? 0) - (p.levels[l.id] ?? 0)) < 0.02
        }
    }
}

private struct LayerSlider: View {
    let layer: Soundscape.LayerInfo
    let dark: Bool
    let theme: TimerTheme
    @Binding var value: Double
    @State private var lastOn: Double = 0.6
    @State private var dragStart: Double? = nil

    var body: some View {
        let on = value > 0.01
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(dark ? Palette.nightChip : Palette.track)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [theme.c1.opacity(0.55), theme.c2.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geo.size.width * value))
                HStack(spacing: 8) {
                    Image(systemName: layer.icon)
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 20)
                        .symbolEffect(.bounce, value: on)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(layer.name).font(.footnote.weight(.semibold)).lineLimit(1)
                        Text(on ? "\(Int((value * 100).rounded()))%" : "Off")
                            .font(.caption2.weight(.bold)).monospacedDigit()
                            .opacity(0.7)
                            .contentTransition(.numericText(value: value))
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(dark ? Palette.nightInk : Color.primary)
                .padding(.horizontal, 12)
            }
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(dark ? Palette.nightLine : .clear, lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if dragStart == nil { dragStart = value }
                        if abs(g.translation.width) < 4 { return }
                        let v = max(0, min(1, (dragStart ?? 0) + Double(g.translation.width / geo.size.width)))
                        if (v == 0 || v == 1) && v != value { Haptics.shared.play(.rigid) }
                        else if Int(v * 10) != Int(value * 10) { Haptics.shared.play(.tick) }
                        value = v
                    }
                    .onEnded { g in
                        defer { dragStart = nil }
                        guard abs(g.translation.width) < 4 else {
                            if value > 0.01 { lastOn = value }
                            return
                        }
                        // A tap toggles.
                        withAnimation(.calm) {
                            if on { lastOn = value; value = 0 } else { value = lastOn }
                        }
                        Haptics.shared.play(.light)
                    }
            )
        }
        .frame(height: 52)
        .accessibilityElement()
        .accessibilityLabel(layer.name)
        .accessibilityValue(on ? "\(Int(value * 100)) percent" : "Off")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: value = min(1, value + 0.1)
            case .decrement: value = max(0, value - 0.1)
            @unknown default: break
            }
        }
    }
}
