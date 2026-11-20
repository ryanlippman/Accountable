import SwiftUI
import UIKit

// MARK: - Shared dark focus pieces

/// The dark backdrop, lit from above and below by the timer color.
struct NightBackdrop: View {
    var theme: TimerTheme
    var intensity: Double = 1

    var body: some View {
        ZStack {
            Palette.night
            RadialGradient(colors: [theme.c2.opacity(0.38 * intensity), .clear], center: UnitPoint(x: 0.5, y: 0.2), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [theme.c1.opacity(0.22 * intensity), .clear], center: UnitPoint(x: 0.5, y: 1.1), startRadius: 0, endRadius: 360)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: intensity)
    }
}

/// Timer ring with minute ticks, like the web focus screen.
struct FocusRing: View {
    var progress: Double
    var theme: TimerTheme
    var glowing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r1 = size.width / 2, r2s = r1 - 4, r2l = r1 - 9
                for i in 0..<60 {
                    let a = Double(i) * 6 * .pi / 180
                    let r2 = i % 5 == 0 ? r2l : r2s
                    var p = Path()
                    p.move(to: CGPoint(x: c.x + r1 * CGFloat(sin(a)), y: c.y - r1 * CGFloat(cos(a))))
                    p.addLine(to: CGPoint(x: c.x + r2 * CGFloat(sin(a)), y: c.y - r2 * CGFloat(cos(a))))
                    ctx.stroke(p, with: .color(.white.opacity(0.14)), style: StrokeStyle(lineWidth: i % 5 == 0 ? 2 : 1, lineCap: .round))
                }
            }
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 14)
                .padding(22)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(theme.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(22)
                .shadow(color: theme.c2.opacity(glowing ? 0.7 : 0.45), radius: glowing ? 16 : 10)
                .animation(.linear(duration: 0.5), value: progress)
                .animation(reduceMotion ? .none : .easeInOut(duration: 0.8), value: glowing)
        }
    }
}

struct PhaseChip: View {
    let text: String
    let theme: TimerTheme

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(theme.gradient).frame(width: 8, height: 8)
            Text(text.uppercased()).font(.system(size: 14, weight: .semibold, design: .rounded)).tracking(2)
        }
        .foregroundStyle(Palette.nightInk)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(Palette.nightChip, in: Capsule())
        .overlay(Capsule().stroke(Palette.nightLine, lineWidth: 1))
    }
}

struct NightStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
                .foregroundStyle(Palette.nightInk)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.3), value: value)
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(Palette.nightMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Palette.nightChip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.nightLine, lineWidth: 1))
    }
}

// MARK: - Focus tab (ready state)

struct FocusTab: View {
    @Environment(AppStore.self) private var store
    @Environment(DrawerCenter.self) private var drawers
    @State private var taskID: UUID? = nil
    @State private var minutes = 20
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sessionNamespace) var sessionNS
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency

    var body: some View {
        let theme = TimerTheme.find(store.data.theme)
        let open = store.openTasks
        let log = store.todayLog
        ZStack {
            NightBackdrop(theme: theme, intensity: 0.6)
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        Text("WORKING ON").font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(Palette.nightMuted)
                        Button {
                            drawers.present(dark: true) {
                                TaskPicker(selected: taskID) { id in
                                    taskID = id
                                    drawers.dismiss()
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(open.first(where: { $0.id == taskID })?.title ?? "Just focus")
                                    .lineLimit(1)
                                    .contentTransition(.opacity)
                                Image(systemName: "chevron.down").font(.caption.weight(.bold))
                            }
                            .font(.headline)
                            .foregroundStyle(Palette.nightInk)
                            .padding(.horizontal, 18).padding(.vertical, 11)
                            .background(Palette.nightChip, in: Capsule())
                            .overlay(Capsule().stroke(Palette.nightLine, lineWidth: 1))
                        }
                        .buttonStyle(PressableStyle(scale: 0.95))
                        .animation(.calm, value: taskID)
                    }
                    .padding(.top, 8)

                    ModeSwitch(stopwatch: Binding(
                        get: { store.data.focusStopwatch },
                        set: { v in withAnimation(.calm) { store.data.focusStopwatch = v } }))
                        .frame(maxWidth: 300)

                    readyDial(theme: theme)

                    VStack(spacing: 14) {
                        if !stopwatch {
                            MinutePicker(minutes: $minutes)
                                .transition(.blurReplace)
                        }
                        Button(action: startSession) {
                            HStack(spacing: 8) {
                                Image(systemName: stopwatch ? "stopwatch.fill" : "play.fill")
                                    .contentTransition(.symbolEffect(.replace))
                                Text(stopwatch ? "Start stopwatch" : "Start \(minutes)-minute session")
                                    .contentTransition(.numericText(value: Double(minutes)))
                            }
                        }
                        .buttonStyle(GlowButtonStyle(theme: theme, dark: true))
                        .zoomSource(sessionNS)
                        if Platform.hasPhoneSensors {
                            Label("Flip your phone face down during focus for +50% XP", systemImage: "iphone.slash")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Palette.nightMuted)
                        }
                    }
                    .frame(maxWidth: 400)
                    .animation(.calm, value: stopwatch)
                    .animation(.calm, value: minutes)

                    HStack(spacing: 8) {
                        NightStat(value: "\(log.focusMinutes)m", label: "Today")
                        NightStat(value: "\(log.sessions)", label: "Sessions")
                        NightStat(value: "×\(log.maxCombo)", label: "Best combo")
                    }
                    .frame(maxWidth: 420)

                    SoundMixer(dark: true, livePreview: true)
                        .padding(16)
                        .background(Palette.nightChip, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Palette.nightLine, lineWidth: 1))
                        .frame(maxWidth: 420)

                    ThemePicker()
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
            }
        }
        .environment(\.colorScheme, .dark)
        .toolbarBackground(Palette.night, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .onAppear {
            minutes = store.data.defaultMinutes
            if taskID == nil { taskID = store.upNext?.id }
        }
        .onDisappear {
            // Stop the preview, unless a session took over the sound.
            if store.sessionRequest == nil { Soundscape.shared.stop() }
        }
    }
}

extension FocusTab {
    fileprivate var stopwatch: Bool { store.data.focusStopwatch }

    fileprivate func startSession() {
        if stopwatch {
            store.sessionRequest = SessionConfig(taskID: taskID, minutes: 0, stopwatch: true)
        } else {
            store.data.defaultMinutes = minutes
            store.sessionRequest = SessionConfig(taskID: taskID, minutes: minutes)
        }
    }

    /// The ring in its ready state. The center cross-fades between the timer length and the stopwatch.
    fileprivate func readyDial(theme: TimerTheme) -> some View {
        ZStack {
            FocusRing(progress: stopwatch ? 0.0 : 1, theme: theme)
            VStack(spacing: 6) {
                Text(stopwatch ? "0:00" : "\(minutes):00")
                    .font(.system(size: 66, weight: .thin, design: .rounded))
                    .tracking(-1)
                    .monospacedDigit()
                    .foregroundStyle(Palette.nightInk)
                    .contentTransition(.numericText(value: Double(stopwatch ? 0 : minutes)))
                Text(stopwatch ? "Counts up. Finish whenever you're done."
                     : (store.data.prework.isEmpty ? "2-minute starter, then focus" : "Checklist, 2-minute starter, then focus"))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.nightMuted)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 50)
        }
        .frame(width: 290, height: 290)
        .animation(.calm, value: theme.id)
        .animation(.spring(response: 0.5, dampingFraction: 1), value: stopwatch)
        .animation(.calm, value: minutes)
    }
}

/// Timer or stopwatch, with the same sliding white pill as the minute picker.
private struct ModeSwitch: View {
    @Binding var stopwatch: Bool
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            option("Timer", "timer", selected: !stopwatch) { stopwatch = false }
            option("Stopwatch", "stopwatch", selected: stopwatch) { stopwatch = true }
        }
        .padding(4)
        .background(Palette.nightChip, in: Capsule())
        .overlay(Capsule().stroke(Palette.nightLine, lineWidth: 1))
    }

    private func option(_ title: String, _ icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.black : Palette.nightInk)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background {
                    if selected {
                        Capsule().fill(Color.white).matchedGeometryEffect(id: "mode", in: ns)
                    }
                }
        }
        .buttonStyle(PressableStyle(haptic: .tick, scale: 0.95))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Segmented minutes with a sliding white pill.
private struct MinutePicker: View {
    @Binding var minutes: Int
    @Namespace private var ns
    private let options = [5, 10, 20, 25, 45, 60]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { m in
                Button {
                    withAnimation(.calm) { minutes = m }
                } label: {
                    Text("\(m)")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(minutes == m ? Color.black : Palette.nightInk)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if minutes == m {
                                Capsule().fill(Color.white).matchedGeometryEffect(id: "m", in: ns)
                            }
                        }
                }
                .buttonStyle(PressableStyle(haptic: .tick, scale: 0.92))
                .accessibilityLabel("\(m) minutes")
                .accessibilityAddTraits(minutes == m ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Palette.nightChip, in: Capsule())
        .overlay(Capsule().stroke(Palette.nightLine, lineWidth: 1))
    }
}

/// Every timer color, owned or not. Locked ones open a small unlock drawer.
private struct ThemePicker: View {
    @Environment(AppStore.self) private var store
    @Environment(DrawerCenter.self) private var drawers

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("TIMER COLOR").font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(Palette.nightMuted)
                Spacer()
                Text("\(store.data.owned.count) of \(TimerTheme.all.count)")
                    .font(.caption.weight(.semibold)).foregroundStyle(Palette.nightMuted).monospacedDigit()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), spacing: 14) {
                ForEach(TimerTheme.all) { t in
                    let owned = store.data.owned.contains(t.id)
                    let current = store.data.theme == t.id
                    Button {
                        if owned {
                            withAnimation(.calm) { store.data.theme = t.id }
                        } else {
                            drawers.present(dark: true) { UnlockTheme(theme: t) }
                        }
                    } label: {
                        ZStack {
                            Circle().fill(t.gradient)
                                .opacity(owned ? 1 : 0.35)
                            if !owned {
                                Image(systemName: "lock.fill").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.9))
                            }
                        }
                        .frame(width: 34, height: 34)
                        .padding(3)
                        .overlay(Circle().stroke(current ? Color.white : .clear, lineWidth: 2))
                        .scaleEffect(current ? 1.06 : 1)
                        .animation(.reward, value: current)
                    }
                    .buttonStyle(PressableStyle(haptic: .tick, scale: 0.86))
                    .accessibilityLabel(t.name + (owned ? "" : ", locked, \(t.price) sparks"))
                    .accessibilityAddTraits(current ? .isSelected : [])
                }
            }
            Text(TimerTheme.find(store.data.theme).name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.nightInk)
                .contentTransition(.opacity)
                .animation(.calm, value: store.data.theme)
        }
        .padding(16)
        .background(Palette.nightChip, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Palette.nightLine, lineWidth: 1))
        .frame(maxWidth: 420)
    }
}

private struct UnlockTheme: View {
    @Environment(AppStore.self) private var store
    @Environment(DrawerCenter.self) private var drawers
    let theme: TimerTheme
    @State private var failed = 0

    var body: some View {
        let can = store.data.sparks >= theme.price
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(theme.gradient).frame(width: 96, height: 96)
                    .shadow(color: theme.c2.opacity(0.6), radius: 24)
                Image(systemName: "timer").font(.system(size: 36, weight: .semibold)).foregroundStyle(.white)
            }
            .modifier(Shake(amount: CGFloat(failed)))
            .padding(.top, 4)
            VStack(spacing: 4) {
                Text(theme.name).font(.title2.weight(.bold)).foregroundStyle(Palette.nightInk)
                Text(can ? "You have \(store.data.sparks) sparks." : "You need \(theme.price - store.data.sparks) more sparks. Quests and loot drops earn them.")
                    .font(.subheadline).foregroundStyle(Palette.nightMuted).multilineTextAlignment(.center)
            }
            Button {
                if store.buy(.theme(theme.id)) {
                    store.confetti += 1
                    Haptics.shared.sparkle()
                    SoundFX.shared.play(.purchase)
                    drawers.dismiss()
                } else {
                    withAnimation(.linear(duration: 0.4)) { failed += 1 }
                    Haptics.shared.play(.error)
                    SoundFX.shared.play(.error)
                }
            } label: {
                Label("Unlock for \(theme.price)", systemImage: "sparkle")
            }
            .buttonStyle(GlowButtonStyle(theme: theme))
            .opacity(can ? 1 : 0.5)
            Button("Not now") { drawers.dismiss() }
                .buttonStyle(SoftButtonStyle(dark: true))
        }
    }
}

private struct TaskPicker: View {
    @Environment(AppStore.self) private var store
    let selected: UUID?
    let pick: (UUID?) -> Void

    var body: some View {
        VStack(spacing: 8) {
            DrawerTitle(title: "What are you working on?")
            ScrollView {
                VStack(spacing: 8) {
                    row(title: "Just focus", icon: "sparkles", id: nil)
                    ForEach(store.openTasks) { t in
                        row(title: t.title, icon: "circle", id: t.id)
                    }
                }
            }
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(title: String, icon: String, id: UUID?) -> some View {
        let on = selected == id
        return Button {
            Haptics.shared.play(.tick)
            pick(id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : icon)
                    .font(.title3)
                    .foregroundStyle(on ? Palette.ember : Palette.nightMuted)
                Text(title).font(.body.weight(.medium)).foregroundStyle(Palette.nightInk).lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(Palette.nightChip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(on ? Palette.ember.opacity(0.6) : Palette.nightLine, lineWidth: 1))
        }
        .buttonStyle(PressableStyle(haptic: .none, scale: 0.98))
    }
}

// MARK: - Session

struct SessionView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: FocusSession
    @State private var reward: SessionReward? = nil
    @State private var showQuit = false
    @State private var comboFlash = 0
    @State private var onTimeFlash = false
    @State private var firstEver = false
    @State private var showSounds = false
    @State private var deskClock = false
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    init(config: SessionConfig, checklist: Bool) {
        _session = State(initialValue: FocusSession(config: config, checklist: checklist))
    }

    private var theme: TimerTheme { TimerTheme.find(store.data.theme) }

    private var taskTitle: String? {
        guard let id = session.config.taskID else { return nil }
        return store.data.tasks.first { $0.id == id }?.title
    }

    var body: some View {
        ZStack {
            NightBackdrop(theme: theme, intensity: session.phase == .focus ? 1 : 0.7)
            if let reward {
                CompleteFlow(reward: reward, theme: theme, firstEver: firstEver) { dismiss() }
                    .transition(.blurReplace(.upUp))
            } else if session.phase == .checklist {
                ChecklistStage(items: store.data.prework, theme: theme, onClose: { dismiss() }) { start() }
                    .transition(.blurReplace)
            } else {
                FocusStage(session: session, theme: theme, taskTitle: taskTitle, shields: store.data.shields,
                           comboFlash: comboFlash, onTimeFlash: onTimeFlash, onFinish: { wrapUp() }) {
                    Haptics.shared.play(.light)
                    showQuit = true
                }
                .scaleEffect(showQuit ? 0.96 : 1)
                .blur(radius: showQuit ? 2 : 0)
                .animation(.drawer, value: showQuit)
                .transition(.blurReplace)
            }
            if reward == nil && session.phase == .focus && !deskClock {
                VStack {
                    Spacer()
                    HStack {
                        roundButton(Soundscape.shared.isPlaying ? "speaker.wave.2.fill" : "speaker.slash.fill", "Soundscape") { showSounds = true }
                        Spacer()
                        roundButton("clock", "Desk clock") { withAnimation(.calm) { deskClock = true } }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
                }
                .transition(.opacity)
            }
            if deskClock && reward == nil {
                DeskClock(session: session, theme: theme, taskTitle: taskTitle) {
                    withAnimation(.calm) { deskClock = false }
                }
                .transition(.opacity)
                .zIndex(2)
            }
            Drawer(isPresented: $showSounds, dark: true) { SoundMixer(dark: true, livePreview: true).padding(.bottom, 8) }
                .zIndex(3)
            Drawer(isPresented: $showQuit, dark: true) { quitPrompt }
                .zIndex(3)
        }
        .environment(\.colorScheme, .dark)
        .animation(.calm, value: reward != nil)
        .animation(.calm, value: session.phase)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if Platform.hasPhoneSensors { UIDevice.current.isProximityMonitoringEnabled = true }
            if session.phase == .starter { start() }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            if Platform.hasPhoneSensors { UIDevice.current.isProximityMonitoringEnabled = false }
            session.stopMotion()
            FocusLive.endAll()
            Soundscape.shared.stop()
            if store.focusForWidget != nil {
                store.focusForWidget = nil
                store.publishWidgets()
            }
        }
        .onChange(of: session.phase) { _, phase in
            if phase == .focus {
                FocusLive.update(liveState())
                updateWidgetClock()
            }
        }
        .onChange(of: session.phaseEnd) { _, _ in
            guard session.isRunning else { return }
            FocusLive.update(liveState())
            updateWidgetClock()
        }
        .onChange(of: session.faceDown) { _, _ in if session.isRunning { FocusLive.update(liveState()) } }
        .onChange(of: session.combo) { _, _ in if session.isRunning { FocusLive.update(liveState()) } }
        .onReceive(ticker) { _ in handleTick() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
            session.noteLocked()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                session.wentAway()
                store.saveNow()
            } else if phase == .active {
                if let reason = session.cameBack(strict: store.data.strict && !Platform.isMac) {
                    store.loseShield(reason)
                }
                handleTick()
            }
        }
    }

    // MARK: Quit drawer

    private var focusedMinutes: Int { Int(session.focusedSeconds / 60) }
    private var canKeep: Bool { session.phase == .focus && focusedMinutes >= 5 }
    private var penalized: Bool { session.phase == .focus && session.focusedSeconds > 60 && !canKeep }

    @ViewBuilder private var quitPrompt: some View {
        VStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 6)
                    Circle().trim(from: 0, to: max(0.001, session.progress))
                        .stroke(theme.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(FocusSession.clock(session.displaySeconds, up: session.countsUp))
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.nightInk)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText(countsDown: !session.countsUp))
                }
            }
            .frame(width: 72, height: 72)
            .padding(.bottom, 6)
            DrawerTitle(title: canKeep ? (session.isStopwatch ? "Finish now?" : "Wrap up early?") : (session.phase == .focus ? "End this session?" : "Stop before you start?"),
                        message: quitMessage)
            Button("Keep going") {
                Haptics.shared.play(.medium)
                showQuit = false
            }
            .buttonStyle(GlowButtonStyle(theme: theme, dark: true))
            if canKeep {
                Button("Finish now and keep \(focusedMinutes) min") { wrapUp() }
                    .buttonStyle(SoftButtonStyle(color: theme.c1, dark: true))
            }
            Button(canKeep ? "End without saving" : "End session") { quit() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(penalized || canKeep ? Palette.bad : Palette.nightMuted)
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(PressableStyle(scale: 0.96))
        }
    }

    private var quitMessage: String {
        if canKeep { return "You've focused \(focusedMinutes) minutes. That's real progress, and you can keep it." }
        if penalized { return "Ending in the first 5 minutes cracks a shield. The next 5 minutes are the hardest part." }
        return "Nothing lost yet. Even two minutes is a good start."
    }

    // MARK: Lock Screen and Dynamic Island

    private func liveState(_ phase: String? = nil) -> FocusActivityAttributes.ContentState {
        let p = phase ?? (session.phase == .starter ? "starter" : (session.phase == .focus ? "focus" : "done"))
        if session.countsUp && p == "focus" {
            // Counting up: start is "now minus what you've focused", so time spent away doesn't count.
            let start = Date().addingTimeInterval(-session.focusedSeconds)
            return FocusActivityAttributes.ContentState(phase: p, start: start, end: start.addingTimeInterval(FocusSession.stopwatchCap),
                                                        combo: session.combo, faceDown: session.faceDown, xp: session.xpSoFar,
                                                        stopwatch: true, lap: session.comboWindowStart)
        }
        let end = session.phaseEnd == .distantFuture ? Date() : session.phaseEnd
        return FocusActivityAttributes.ContentState(phase: p, start: end.addingTimeInterval(-session.phaseLength), end: end,
                                                    combo: session.combo, faceDown: session.faceDown, xp: session.xpSoFar,
                                                    stopwatch: session.isStopwatch, lap: session.comboWindowStart)
    }

    /// Keeps the StandBy timer widget in step with the round.
    private func updateWidgetClock() {
        if session.isRunning {
            let s = liveState()
            store.focusForWidget = (s.start, s.end, taskTitle ?? "Free focus", session.countsUp)
        } else {
            store.focusForWidget = nil
        }
        store.publishWidgets()
    }

    private func roundButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Palette.nightMuted)
                .frame(width: 44, height: 44)
                .background(Palette.nightChip, in: Circle())
                .overlay(Circle().stroke(Palette.nightLine, lineWidth: 1))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableStyle(scale: 0.88))
        .accessibilityLabel(label)
    }

    /// `xp` is what the session actually paid out, so the Lock Screen shows the real number.
    private func wrapUpExtras(xp: Int) {
        Soundscape.shared.stop()
        store.focusForWidget = nil
        store.publishWidgets()
        withAnimation(.calm) { deskClock = false }
        var done = liveState("done")
        done.xp = xp
        FocusLive.finish(done)
    }

    private func start() {
        withAnimation(.calm) { session.begin() }
        FocusLive.start(title: taskTitle ?? "Free focus", minutes: session.config.minutes, theme: theme, state: liveState())
        updateWidgetClock()
        if store.data.soundOn { Soundscape.shared.play(store.data.soundLevels, master: store.data.soundMaster) }
        if store.beginSession(session.config) {
            session.onTime = true
            onTimeFlash = true
            Haptics.shared.play(.success)
        }
        SoundFX.shared.play(.start)
        Haptics.shared.play(.heavy)
    }

    private func handleTick() {
        guard reward == nil, let event = session.tick() else { return }
        switch event {
        case .starterDone:
            Haptics.shared.play(.success)
            SoundFX.shared.play(.start)
        case .combo(let n):
            comboFlash += 1
            Haptics.shared.combo()
            SoundFX.shared.play(.combo(n))
        case .countdown:
            Haptics.shared.countdown()
        case .finished:
            complete()
        }
    }

    private func complete() {
        firstEver = store.data.sessions.isEmpty
        let r = store.completeSession(SessionResult(
            config: session.config, started: session.started,
            focusedMinutes: max(1, Int((session.focusedSeconds / 60).rounded())),
            maxCombo: session.maxCombo, distractions: session.distractions,
            phoneDownRatio: session.phoneDownRatio, onTime: session.onTime))
        wrapUpExtras(xp: r.total)
        withAnimation(.calm) { reward = r }
        store.confetti += 1
        Haptics.shared.fanfare(steps: 8)
        SoundFX.shared.play(.complete)
    }

    private func wrapUp() {
        showQuit = false
        firstEver = store.data.sessions.isEmpty
        let r = store.completeSession(SessionResult(
            config: session.config, started: session.started,
            focusedMinutes: max(1, focusedMinutes),
            maxCombo: session.maxCombo, distractions: session.distractions,
            phoneDownRatio: session.phoneDownRatio, onTime: session.onTime))
        session.finish()
        wrapUpExtras(xp: r.total)
        withAnimation(.calm) { reward = r }
        Haptics.shared.fanfare(steps: 5)
        SoundFX.shared.play(.complete)
    }

    private func quit() {
        let p = penalized
        session.abandon()
        FocusLive.endAll()
        Soundscape.shared.stop()
        if p { store.loseShield("Ended a focus session early") }
        showQuit = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { dismiss() }
    }
}

// MARK: - Checklist

private struct ChecklistStage: View {
    let items: [String]
    let theme: TimerTheme
    let onClose: () -> Void
    let onStart: () -> Void
    @State private var checked: Set<Int> = []

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.headline).foregroundStyle(Palette.nightMuted)
                        .frame(width: 40, height: 40)
                        .background(Palette.nightChip, in: Circle())
                }
                .buttonStyle(PressableStyle(scale: 0.88))
                Spacer()
                Text("\(checked.count) of \(items.count)").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.nightMuted).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Pre-work checklist").font(.largeTitle.weight(.bold)).foregroundStyle(Palette.nightInk)
                Text("Check every box to start.").font(.subheadline).foregroundStyle(Palette.nightMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                        let on = checked.contains(i)
                        Button {
                            withAnimation(.reward) {
                                if on { checked.remove(i) } else { checked.insert(i) }
                            }
                            if !on {
                                SoundFX.shared.play(.pop)
                                Haptics.shared.play(checked.count == items.count ? .success : .rigid)
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(on ? AnyShapeStyle(theme.gradient) : AnyShapeStyle(Palette.nightMuted))
                                    .contentTransition(.symbolEffect(.replace))
                                Text(item).font(.body.weight(.medium)).foregroundStyle(Palette.nightInk).multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .padding(16)
                            .background(Palette.nightChip, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(on ? theme.c1.opacity(0.6) : Palette.nightLine, lineWidth: 1))
                        }
                        .buttonStyle(PressableStyle(haptic: .none, scale: 0.98))
                    }
                }
            }
            Button("Start session", action: onStart)
                .buttonStyle(GlowButtonStyle(theme: theme, dark: true))
                .disabled(checked.count < items.count)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

// MARK: - Focus

private struct FocusStage: View {
    let session: FocusSession
    let theme: TimerTheme
    let taskTitle: String?
    let shields: Int
    let comboFlash: Int
    let onTimeFlash: Bool
    let onFinish: () -> Void
    let onQuit: () -> Void
    @State private var comboScale: CGFloat = 1

    private var focusedMinutes: Int { Int(session.focusedSeconds / 60) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            VStack(spacing: 16) {
                topBar
                Text(session.phase == .starter ? "JUST BEGIN" : (taskTitle ?? "Free focus").uppercased())
                    .font(.caption.weight(.bold)).tracking(1.5)
                    .foregroundStyle(Palette.nightMuted)
                    .lineLimit(1)
                PhaseChip(text: session.phase == .starter ? "Starter" : (session.faceDown ? "Phone down" : "Focus"), theme: theme)
                if let b = session.banner {
                    Label(b, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Palette.bad.opacity(0.85), in: Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                ZStack {
                    FocusRing(progress: session.progress, theme: theme, glowing: session.phase == .focus)
                    VStack(spacing: 6) {
                        Text(FocusSession.clock(session.displaySeconds, up: session.countsUp))
                            .font(.system(size: session.displaySeconds >= 3600 ? 54 : 70, weight: .thin, design: .rounded))
                            .tracking(-1)
                            .monospacedDigit()
                            .foregroundStyle(Palette.nightInk)
                            .contentTransition(.numericText(countsDown: !session.countsUp))
                            // Each second rolls into place instead of snapping.
                            .animation(.snappy(duration: 0.28), value: Int(session.displaySeconds))
                        Text(subtitle)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Palette.nightMuted)
                            .contentTransition(.opacity)
                            .animation(.calm, value: subtitle)
                    }
                    if onTimeFlash {
                        Text("On time · +15 XP")
                            .font(.caption.weight(.bold)).foregroundStyle(.black)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.white, in: Capsule())
                            .offset(y: -128)
                    }
                }
                .frame(width: 300, height: 300)
                Spacer(minLength: 0)
                comboTrack
                if Platform.hasPhoneSensors { phoneDownPill }
                HStack(spacing: 8) {
                    NightStat(value: "+\(session.xpSoFar)", label: "XP so far")
                    NightStat(value: "×\(session.combo)", label: "Combo")
                    NightStat(value: "\(session.distractions)", label: "Distractions")
                }
                if session.phase == .starter {
                    Button("Skip starter") {
                        withAnimation(.calm) { session.startFocus() }
                        SoundFX.shared.play(.start)
                        Haptics.shared.play(.medium)
                    }
                    .buttonStyle(GlowButtonStyle(theme: theme, dark: true))
                } else if session.isStopwatch {
                    // A stopwatch ends when you say so. Five minutes in, finishing keeps every minute.
                    if focusedMinutes >= 5 {
                        Button {
                            onFinish()
                        } label: {
                            Label("Finish · keep \(focusedMinutes) min", systemImage: "checkmark")
                                .contentTransition(.numericText(value: Double(focusedMinutes)))
                        }
                        .buttonStyle(GlowButtonStyle(theme: theme, dark: true))
                        .transition(.blurReplace)
                    } else {
                        Button("End session", action: onQuit)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.nightMuted)
                            .frame(height: 54)
                            .transition(.blurReplace)
                    }
                } else {
                    Button("End session", action: onQuit)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.nightMuted)
                        .frame(height: 54)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .onChange(of: comboFlash) { _, _ in
            comboScale = 1.5
            withAnimation(.reward) { comboScale = 1 }
        }
    }

    private var subtitle: String {
        if session.phase == .starter { return "Nothing else required" }
        if session.faceDown { return "Phone down. Nice." }
        if session.isStopwatch {
            let left = Int((1 - session.comboProgress) * FocusSession.comboInterval)
            return "Next combo in \(left / 60):" + String(format: "%02d", left % 60)
        }
        return "\(Int(session.focusedSeconds / 60)) of \(session.config.minutes) min"
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onQuit) {
                Image(systemName: "xmark").font(.headline).foregroundStyle(Palette.nightMuted)
                    .frame(width: 40, height: 40)
                    .background(Palette.nightChip, in: Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.88))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(theme.gradient)
                        .frame(width: geo.size.width * (session.phase == .focus ? session.progress : 0))
                        .animation(.linear(duration: 0.5), value: session.progress)
                }
            }
            .frame(height: 8)
            HStack(spacing: 4) {
                Image(systemName: "shield.lefthalf.filled").foregroundStyle(Palette.shield)
                Text("\(shields)").monospacedDigit().foregroundStyle(Palette.nightInk)
            }
            .font(.subheadline.weight(.bold))
        }
    }

    /// One segment per 5 minutes of the round; each fills as the combo grows.
    private var comboTrack: some View {
        // A stopwatch has no fixed length: show the combos earned plus the one you're working toward.
        let segments = session.isStopwatch ? min(12, max(6, session.combo + 1)) : max(1, session.config.minutes / 5)
        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").foregroundStyle(session.combo > 0 ? AnyShapeStyle(theme.gradient) : AnyShapeStyle(Palette.nightMuted))
                Text(session.combo > 0 ? "×\(session.combo) combo" : "Combo every 5 min").font(.subheadline.weight(.semibold))
                    .foregroundStyle(session.combo > 0 ? Palette.nightInk : Palette.nightMuted)
            }
            .scaleEffect(comboScale)
            HStack(spacing: 5) {
                ForEach(0..<segments, id: \.self) { i in
                    Capsule()
                        .fill(i < session.combo ? AnyShapeStyle(theme.gradient) : AnyShapeStyle(Color.white.opacity(0.08)))
                        .frame(height: 5)
                }
            }
            .frame(maxWidth: 320)
        }
        .opacity(session.phase == .focus ? 1 : 0.35)
    }

    private var phoneDownPill: some View {
        Label(session.faceDown ? "Phone down · +50% XP" : "Flip your phone face down for +50% XP",
              systemImage: session.faceDown ? "iphone.slash" : "arrow.down.to.line")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(session.faceDown ? Color.black : Palette.nightMuted)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(session.faceDown ? AnyShapeStyle(Color.white) : AnyShapeStyle(Palette.nightChip), in: Capsule())
            .animation(.calm, value: session.faceDown)
            .opacity(session.phase == .focus ? 1 : 0)
    }
}

// MARK: - Complete

private struct CompleteFlow: View {
    let reward: SessionReward
    let theme: TimerTheme
    var firstEver = false
    let onDone: () -> Void
    @State private var step = 0

    var body: some View {
        ZStack {
            if step == 0 {
                Summary(reward: reward, theme: theme, firstEver: firstEver) {
                    if reward.firstToday && reward.streakAfter > 0 { withAnimation(.calm) { step = 1 } } else { onDone() }
                }
                .transition(.opacity.combined(with: .move(edge: .leading)))
            } else {
                StreakStage(before: reward.streakBefore, after: reward.streakAfter, theme: theme, onContinue: onDone)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
    }
}

private struct Summary: View {
    let reward: SessionReward
    let theme: TimerTheme
    var firstEver = false
    let onContinue: () -> Void
    @State private var shown = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 10)
            Image(systemName: reward.shieldRestored ? "shield.lefthalf.filled" : "checkmark.circle.fill")
                .font(.system(size: 84))
                .foregroundStyle(theme.gradient)
                .symbolEffect(.bounce, value: shown)
                .scaleEffect(shown ? 1 : 0.5)
                .opacity(shown ? 1 : 0)
            Text(reward.shieldRestored ? "Shield restored" : "Session complete")
                .font(.largeTitle.weight(.bold)).foregroundStyle(Palette.nightInk)
            Text(firstEver ? "You started the thing you'd been putting off. That's progress." : reward.comeback ? "You came back. That's the hardest part." : (reward.distractions == 0 ? "Not a single distraction." : "You pushed through. That's what counts."))
                .font(.subheadline).foregroundStyle(Palette.nightMuted)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Tile(title: reward.boosted ? "XP ×2" : "XP", value: reward.total, suffix: "", delay: 0.25)
                Tile(title: "Focused", value: reward.focusedMinutes, suffix: "m", delay: 0.45)
                if reward.phoneDownRatio > 0 {
                    Tile(title: "Phone down", value: Int(reward.phoneDownRatio * 100), suffix: "%", delay: 0.65)
                } else {
                    Tile(title: "Top combo", value: reward.maxCombo, suffix: "×", delay: 0.65)
                }
            }
            VStack(spacing: 8) {
                ForEach(Array(reward.lines.enumerated()), id: \.offset) { i, line in
                    HStack {
                        Text(line.0).foregroundStyle(Palette.nightMuted)
                        Spacer()
                        Text("+\(line.1)").foregroundStyle(Palette.nightInk).monospacedDigit()
                    }
                    .font(.subheadline.weight(.medium))
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 8)
                    .animation(.calm.delay(0.8 + Double(i) * 0.07), value: shown)
                }
                if reward.halved {
                    Text("Out of shields, so this one earned half XP. A 5-minute recovery session wins one back.")
                        .font(.footnote).foregroundStyle(Palette.bad)
                }
            }
            .padding(16)
            .background(Palette.nightChip, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer(minLength: 0)
            Button("Continue", action: onContinue)
                .buttonStyle(GlowButtonStyle(theme: theme, dark: true))
        }
        .padding(20)
        .onAppear { withAnimation(.reward) { shown = true } }
    }
}

private struct Tile: View {
    let title: String
    let value: Int
    let suffix: String
    let delay: Double
    @State private var shown = false

    var body: some View {
        VStack(spacing: 4) {
            if shown {
                CountUpText(target: value, font: .system(size: 30, weight: .bold, design: .rounded), color: Palette.nightInk, suffix: suffix)
            } else {
                Text(" ").font(.system(size: 30, weight: .bold, design: .rounded))
            }
            Text(title.uppercased()).font(.caption2.weight(.bold)).tracking(1).foregroundStyle(Palette.nightMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Palette.nightChip, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.nightLine, lineWidth: 1))
        .scaleEffect(shown ? 1 : 0.85)
        .opacity(shown ? 1 : 0)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.reward) { shown = true }
                Haptics.shared.play(.heavy)
                SoundFX.shared.play(.xp)
            }
        }
    }
}

private struct StreakStage: View {
    let before: Int
    let after: Int
    let theme: TimerTheme
    let onContinue: () -> Void
    @State private var value: Int
    @State private var lit = false

    init(before: Int, after: Int, theme: TimerTheme, onContinue: @escaping () -> Void) {
        self.before = before
        self.after = after
        self.theme = theme
        self.onContinue = onContinue
        _value = State(initialValue: before)
    }

    private var week: [(String, Bool, Bool)] {
        let wd = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        return (0..<7).map { i in (letters[i], i < wd && i >= wd - (after - 1), i == wd) }
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "flame.fill")
                .font(.system(size: 120))
                .foregroundStyle(theme.gradient)
                .shadow(color: theme.c2.opacity(lit ? 0.7 : 0), radius: 30)
                .symbolEffect(.bounce, value: lit)
                .scaleEffect(lit ? 1 : 0.6)
            Text("\(value)")
                .font(.system(size: 84, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.nightInk)
                .contentTransition(.numericText(value: Double(value)))
            Text("day streak").font(.title2.weight(.semibold)).foregroundStyle(Palette.nightMuted)
            HStack(spacing: 10) {
                ForEach(Array(week.enumerated()), id: \.offset) { _, d in
                    let filled = d.1 || (d.2 && lit)
                    VStack(spacing: 6) {
                        Text(d.0).font(.caption.weight(.bold)).foregroundStyle(d.2 ? Palette.nightInk : Palette.nightMuted)
                        Circle()
                            .fill(filled ? AnyShapeStyle(theme.gradient) : AnyShapeStyle(Color.white.opacity(0.08)))
                            .frame(width: 28, height: 28)
                            .overlay(Image(systemName: "checkmark").font(.caption.weight(.heavy)).foregroundStyle(.white).opacity(filled ? 1 : 0))
                            .scaleEffect(d.2 && lit ? 1.12 : 1)
                    }
                }
            }
            .padding(16)
            .background(Palette.nightChip, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text(after == 1 ? "Day one. Every streak starts here." : "Come back tomorrow to keep it going.")
                .font(.subheadline).foregroundStyle(Palette.nightMuted)
            Spacer()
            Button("Continue", action: onContinue)
                .buttonStyle(GlowButtonStyle(theme: theme, dark: true))
        }
        .padding(20)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.reward) {
                    lit = true
                    value = after
                }
                Haptics.shared.fanfare()
                SoundFX.shared.play(.streak)
            }
        }
    }
}
