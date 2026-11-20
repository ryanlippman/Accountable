import AVFoundation
import Speech
import Observation

/// Listens for as long as you talk and keeps everything it hears.
///
/// Speech recognition tasks end on their own (after a pause, a time limit, or a hiccup), so whenever one
/// ends while you're still holding the button, its text is kept and a fresh task picks up where it left
/// off. Recognition runs on the device when the phone supports it, so it works offline and has no time limit.
@Observable
final class VoiceRecorder {
    enum State: Equatable { case idle, listening, finishing }

    var state: State = .idle
    /// Everything finished so far.
    var committed = ""
    /// What's being heard right now; it can still change.
    var partial = ""
    /// Recent loudness, newest last, 0...1, for the waveform.
    var levels: [CGFloat] = Array(repeating: 0, count: 42)
    var problem: String? = nil

    var transcript: String {
        [committed, partial].filter { !$0.isEmpty }.joined(separator: " ")
    }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private let lock = NSLock()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var restarts: [Date] = []
    @ObservationIgnored private var lastLevel = Date.distantPast
    @ObservationIgnored private var smoothed: Float = 0
    @ObservationIgnored private var finishWaiter: CheckedContinuation<Void, Never>?

    // MARK: Permission

    static var hasPermission: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized && AVAudioApplication.shared.recordPermission == .granted
    }

    static var wasDenied: Bool {
        SFSpeechRecognizer.authorizationStatus() == .denied || AVAudioApplication.shared.recordPermission == .denied
    }

    static func requestPermission() async -> Bool {
        let speech: Bool = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        return speech && mic
    }

    // MARK: Recording

    func start() {
        guard state == .idle else { return }
        problem = nil
        let r = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let r, r.isAvailable else {
            problem = "Speech recognition isn't available right now. You can type instead."
            return
        }
        recognizer = r
        do {
            let session = AVAudioSession.sharedInstance()
            #if targetEnvironment(macCatalyst)
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers])
            #else
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            #endif
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                problem = "No microphone found."
                return
            }
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.consume(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            problem = "Couldn't start the microphone."
            restoreAudio()
            return
        }
        state = .listening
        restarts = []
        beginRecognition()
    }

    /// Stops listening, waits a moment for the last words to land, and returns everything heard.
    @MainActor
    func stop() async -> String {
        guard state == .listening else { return transcript }
        state = .finishing
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        lock.lock(); request?.endAudio(); lock.unlock()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            finishWaiter = c
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.resumeFinish() }
        }
        generation += 1
        task?.cancel()
        task = nil
        lock.lock(); request = nil; lock.unlock()
        state = .idle
        levels = Array(repeating: 0, count: levels.count)
        restoreAudio()
        return transcript
    }

    /// Throws away everything, e.g. when closing the screen.
    func cancel() {
        generation += 1
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        task?.cancel()
        task = nil
        lock.lock(); request = nil; lock.unlock()
        resumeFinish()
        state = .idle
        restoreAudio()
    }

    func reset() {
        committed = ""
        partial = ""
    }

    // MARK: Internals

    private func beginRecognition() {
        guard let recognizer else { return }
        generation += 1
        let gen = generation
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        req.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        lock.lock(); request = req; lock.unlock()
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                if let result {
                    self.partial = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.segmentEnded()
                        return
                    }
                }
                if error != nil { self.segmentEnded() }
            }
        }
    }

    /// One recognition task finished: keep its words, and keep listening if the button's still held.
    private func segmentEnded() {
        commitPartial()
        switch state {
        case .listening:
            let now = Date()
            restarts = restarts.filter { now.timeIntervalSince($0) < 4 } + [now]
            if restarts.count > 6 {
                problem = "Having trouble hearing. Check the mic and try again."
                Task { @MainActor in _ = await self.stop() }
                return
            }
            beginRecognition()
        case .finishing:
            resumeFinish()
        case .idle:
            break
        }
    }

    private func commitPartial() {
        let p = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        partial = ""
        guard !p.isEmpty else { return }
        committed = committed.isEmpty ? p : committed + " " + p
    }

    private func resumeFinish() {
        guard let w = finishWaiter else { return }
        finishWaiter = nil
        commitPartial()
        w.resume()
    }

    /// Runs on the audio thread.
    private func consume(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        request?.append(buffer)
        lock.unlock()

        guard let data = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        for i in stride(from: 0, to: n, by: 2) { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(max(1, n / 2)))
        let db = 20 * log10(max(rms, 0.000_01))
        let level = max(0, min(1, (db + 55) / 45))
        smoothed = smoothed * 0.55 + level * 0.45
        let value = CGFloat(smoothed)
        let now = Date()
        guard now.timeIntervalSince(lastLevel) > 0.045 else { return }
        lastLevel = now
        DispatchQueue.main.async { [weak self] in
            guard let self, self.state == .listening else { return }
            self.levels.removeFirst()
            self.levels.append(value)
        }
    }

    private func restoreAudio() {
        let s = AVAudioSession.sharedInstance()
        try? s.setActive(false, options: .notifyOthersOnDeactivation)
        try? s.setCategory(.ambient, options: [.mixWithOthers])
    }
}
