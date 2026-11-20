import SwiftUI
import CoreMotion
import Observation

/// The live state of one focus session: checklist, 2-minute starter, then the focus round.
/// Time is tracked by end dates, so the timer keeps going while the phone is locked.
@Observable
final class FocusSession {
    enum Phase: Equatable { case checklist, starter, focus, done }
    enum Event { case starterDone, combo(Int), finished, countdown }

    let config: SessionConfig
    var phase: Phase
    var phaseEnd = Date.distantFuture
    var phaseLength: TimeInterval = 120
    var started = Date()
    var focusStart: Date? = nil
    var lostSeconds: TimeInterval = 0
    var combo = 0
    var maxCombo = 0
    var distractions = 0
    var phoneDownSeconds: Double = 0
    var faceDown = false
    var banner: String? = nil
    var onTime = false

    @ObservationIgnored private var lastComboAt: Date? = nil
    private let motion = CMMotionManager()
    @ObservationIgnored private var awayAt: Date? = nil
    @ObservationIgnored private var lockedWhileAway = false
    @ObservationIgnored private var lockSignalAt: Date? = nil
    @ObservationIgnored private var lastTick = Date()
    @ObservationIgnored private var countdownPlayed = false

    init(config: SessionConfig, checklist: Bool) {
        self.config = config
        self.phase = checklist ? .checklist : .starter
    }

    /// The longest a stopwatch round can run before it wraps itself up.
    static let stopwatchCap: TimeInterval = 4 * 3600
    /// A combo lands every five minutes of unbroken focus.
    static let comboInterval: TimeInterval = 300

    var isStopwatch: Bool { config.stopwatch }
    /// True while the clock is counting up rather than down.
    var countsUp: Bool { isStopwatch && phase == .focus }
    var isRunning: Bool { phase == .starter || phase == .focus }
    var remaining: TimeInterval { max(0, phaseEnd.timeIntervalSinceNow) }

    /// How the main ring fills. A timer fills toward the end; a stopwatch fills toward the next combo.
    var progress: Double {
        guard isRunning else { return 0 }
        if countsUp { return comboProgress }
        return min(1, max(0, 1 - remaining / phaseLength))
    }

    /// 0...1 toward the next combo.
    var comboProgress: Double {
        guard phase == .focus, let c = lastComboAt else { return 0 }
        return min(1, max(0, Date().timeIntervalSince(c) / FocusSession.comboInterval))
    }

    /// When the current combo window started (for the Lock Screen ring).
    var comboWindowStart: Date { lastComboAt ?? Date() }

    /// The number the big clock shows: time left on a timer, time focused on a stopwatch.
    var displaySeconds: TimeInterval { countsUp ? focusedSeconds : remaining }

    var focusedSeconds: TimeInterval {
        guard let s = focusStart else { return 0 }
        return max(0, min(phaseLength, Date().timeIntervalSince(s) - lostSeconds))
    }

    var phoneDownRatio: Double {
        let f = focusedSeconds
        return f > 30 ? min(1, phoneDownSeconds / f) : 0
    }

    /// Live XP estimate shown during the round.
    var xpSoFar: Int { Int(focusedSeconds / 60) + combo * 3 }

    // MARK: Phases

    func begin() {
        started = Date()
        if config.recovery { startFocus() } else { startStarter() }
    }

    private func startStarter() {
        phase = .starter
        phaseLength = 120
        phaseEnd = Date().addingTimeInterval(phaseLength)
        startMotion()
    }

    func startFocus() {
        phase = .focus
        phaseLength = isStopwatch ? FocusSession.stopwatchCap : TimeInterval(config.minutes * 60)
        phaseEnd = Date().addingTimeInterval(phaseLength)
        focusStart = Date()
        lostSeconds = 0
        lastComboAt = Date()
        combo = 0
        countdownPlayed = false
        startMotion()
        // A stopwatch has no end to announce.
        if !isStopwatch { Notifier.scheduleSessionEnd(at: phaseEnd) }
    }

    func finish() {
        phase = .done
        stopMotion()
        Notifier.cancelSessionEnd()
    }

    func abandon() {
        stopMotion()
        Notifier.cancelSessionEnd()
    }

    /// Called twice a second. Returns anything worth celebrating.
    func tick() -> Event? {
        let now = Date()
        let dt = min(2, now.timeIntervalSince(lastTick))
        lastTick = now
        if phase == .focus && faceDown { phoneDownSeconds += dt }
        switch phase {
        case .starter:
            if now >= phaseEnd { startFocus(); return .starterDone }
        case .focus:
            if now >= phaseEnd { finish(); return .finished }
            if !isStopwatch && !countdownPlayed && remaining <= 3.2 { countdownPlayed = true; return .countdown }
            if let c = lastComboAt, now.timeIntervalSince(c) >= FocusSession.comboInterval {
                combo += 1
                maxCombo = max(maxCombo, combo)
                lastComboAt = c.addingTimeInterval(FocusSession.comboInterval)
                return .combo(combo)
            }
        default:
            break
        }
        return nil
    }

    // MARK: Phone down

    private func startMotion() {
        guard Platform.hasPhoneSensors, motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 0.5
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let g = m?.gravity else { return }
            let down = g.z > 0.8
            if down != self.faceDown {
                self.faceDown = down
                if self.phase == .focus { Haptics.shared.play(down ? .success : .light) }
            }
        }
    }

    func stopMotion() {
        if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
        faceDown = false
    }

    // MARK: Leaving the app

    /// The screen locked (iOS reports this when protected data becomes unavailable).
    func noteLocked() {
        if awayAt != nil { lockedWhileAway = true } else { lockSignalAt = Date() }
    }

    func wentAway() {
        guard isRunning, awayAt == nil else { return }
        awayAt = Date()
        lockedWhileAway = (lockSignalAt.map { Date().timeIntervalSince($0) < 3 }) ?? false
        lockSignalAt = nil
    }

    /// Coming back. Locking the phone is fine; switching to another app costs a heart and the time is added back.
    /// Returns a heart-loss reason when the trip away counts as a distraction.
    func cameBack(strict: Bool) -> String? {
        guard let at = awayAt else { return nil }
        awayAt = nil
        let away = Date().timeIntervalSince(at)
        if lockedWhileAway {
            lockedWhileAway = false
            if phase == .focus { phoneDownSeconds += min(away, focusedSeconds) }
            return nil
        }
        guard phase == .focus, strict, away >= 10 else { return nil }
        distractions += 1
        combo = 0
        lastComboAt = Date()
        let added = min(away, 3600)
        phaseEnd = phaseEnd.addingTimeInterval(added)
        lostSeconds += added
        if !isStopwatch { Notifier.scheduleSessionEnd(at: phaseEnd) }
        banner = "You left for \(FocusSession.clock(away)). That time was added back."
        return "Left the app during a focus session"
    }

    /// m:ss, or h:mm:ss once a stopwatch passes an hour. Counting up rounds down so 0:59 never reads 1:00.
    static func clock(_ s: TimeInterval, up: Bool = false) -> String {
        let total = Int(up ? s.rounded(.down) : s.rounded(.up))
        if total >= 3600 {
            return "\(total / 3600):" + String(format: "%02d:%02d", total % 3600 / 60, total % 60)
        }
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}
