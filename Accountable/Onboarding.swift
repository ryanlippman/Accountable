import SwiftUI
import UserNotifications

/// Setup in six focused screens. Every answer changes something you'll actually see,
/// every screen can be skipped, and it ends with one real, tiny win.
struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @Environment(DrawerCenter.self) private var drawers
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Step: Int, CaseIterable { case welcome, obstacles, outcome, system, protect, firstWin, plan }

    @State private var step: Step = .welcome
    @State private var forward = true
    @State private var obstacles: Set<String> = []
    @State private var outcome = ""
    @State private var reminder = "evening"
    @State private var minutes = 10
    @State private var planHelp = true
    @State private var thing = ""
    @State private var tiny = ""
    @State private var shrunk = false
    @State private var taskID: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome { topBar.transition(.opacity) }
            ZStack {
                content
                    .id(step)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(background.ignoresSafeArea())
        .animation(.calm, value: step)
        .sensoryFeedback(.selection, trigger: step)
    }

    private var background: some View {
        ZStack {
            Palette.bg
            RadialGradient(colors: [Palette.ember.opacity(step == .welcome ? 0.22 : 0.08), .clear],
                           center: .top, startRadius: 0, endRadius: 520)
                .animation(.easeInOut(duration: 0.6), value: step)
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { go(Step(rawValue: step.rawValue - 1) ?? .welcome) } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(Palette.track, in: Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.88))
            .accessibilityLabel("Back")
            Bar(value: Double(step.rawValue + 1) / Double(Step.allCases.count), color: Palette.ember, height: 6)
            Button("Skip") { skip() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(height: 40)
                .opacity(step == .plan ? 0 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: welcome
        case .obstacles: obstaclesStep
        case .outcome: outcomeStep
        case .system: systemStep
        case .protect: ProtectStep(next: { go(.firstWin) })
        case .firstWin: firstWinStep
        case .plan: planStep
        }
    }

    // MARK: 1. Welcome

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            Image("Mark")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Palette.rose.opacity(0.35), radius: 24, y: 10)
                .padding(.bottom, 28)
            Text("Your brain isn't a to-do list.")
                .font(.system(size: 36, weight: .bold))
                .tracking(-0.6)
                .multilineTextAlignment(.center)
                .padding(.bottom, 14)
            Text("Accountable turns scattered thoughts into tiny next steps, then helps you actually start them.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Let's make this easier.") { go(.obstacles) }
                .buttonStyle(GlowButtonStyle())
            Button("I'll set it up later") { skip() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(height: 48)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }

    // MARK: 2. Obstacles

    private static let obstacleOptions: [(String, String, String)] = [
        ("start", "Starting tasks", "play.circle.fill"),
        ("focus", "Staying focused", "scope"),
        ("remember", "Remembering things", "brain.head.profile"),
        ("prioritize", "Figuring out what to do first", "list.number"),
        ("routines", "Keeping routines", "repeat.circle.fill"),
        ("comeback", "Getting back on track", "arrow.uturn.backward.circle.fill")
    ]

    private var obstaclesStep: some View {
        StepPage(title: "What tends to get in your way?", subtitle: "Pick any that fit. There's no wrong answer.",
                 primary: obstacles.isEmpty ? "Skip for now" : "Continue", action: { go(.outcome) }) {
            ForEach(Self.obstacleOptions.indices, id: \.self) { i in
                let o = Self.obstacleOptions[i]
                OptionRow(title: o.1, icon: o.2, selected: obstacles.contains(o.0), multi: true) {
                    if obstacles.contains(o.0) { obstacles.remove(o.0) } else { obstacles.insert(o.0) }
                }
            }
        }
    }

    // MARK: 3. Outcome

    private static let outcomeOptions: [(String, String, String)] = [
        ("next", "Knowing what to do next", "signpost.right.fill"),
        ("start", "Actually getting started", "bolt.fill"),
        ("finish", "Finishing what I start", "checkmark.seal.fill"),
        ("remember", "Fewer things slipping through", "tray.full.fill"),
        ("routines", "Steadier days and routines", "sun.horizon.fill"),
        ("calm", "Feeling less behind", "leaf.fill")
    ]

    private var outcomeStep: some View {
        StepPage(title: "What would make your days feel easier?", subtitle: "Choose the one that matters most right now.",
                 primary: outcome.isEmpty ? "Skip for now" : "Continue", action: { go(.system) }) {
            ForEach(Self.outcomeOptions.indices, id: \.self) { i in
                let o = Self.outcomeOptions[i]
                OptionRow(title: o.1, icon: o.2, selected: outcome == o.0, multi: false) {
                    outcome = outcome == o.0 ? "" : o.0
                }
            }
        }
    }

    // MARK: 4. Personal system

    private var systemStep: some View {
        StepPage(title: "Let's build your system", subtitle: "You can change any of this later.",
                 primary: "This looks right", action: { go(.protect) }) {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Gentle reminder")
                SegmentRow(options: [("morning", "Morning"), ("afternoon", "Afternoon"), ("evening", "Evening"), ("none", "None")],
                           selection: $reminder)
            }
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Focus sessions")
                SegmentRow(options: [("5", "5 min"), ("10", "10 min"), ("20", "20 min")],
                           selection: Binding(get: { "\(minutes)" }, set: { minutes = Int($0) ?? 10 }))
            }
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Planning help")
                SegmentRow(options: [("yes", "Pick for me"), ("no", "I'll choose")],
                           selection: Binding(get: { planHelp ? "yes" : "no" }, set: { planHelp = $0 == "yes" }))
            }
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Your setup", color: Palette.ember)
                    .padding(.top, 8)
                ForEach(previews, id: \.title) { p in
                    PreviewCard(icon: p.icon, color: p.color, title: p.title, detail: p.detail)
                }
            }
        }
    }

    private struct Preview { let icon: String; let color: Color; let title: String; let detail: String }

    private var previews: [Preview] {
        var list: [Preview] = []
        let launch = planHelp
            ? "Today opens on one next step, picked for you. No scanning a whole list."
            : "Today shows your list in order, and you choose where to start."
        list.append(Preview(icon: "paperplane.fill", color: Palette.ember, title: "Task launchpad", detail: launch))
        let focus = obstacles.contains("focus")
            ? "\(minutes)-minute rounds with a 2-minute warm-up. Stop early and keep what you did."
            : "\(minutes)-minute rounds you can stretch when you're in the zone."
        list.append(Preview(icon: "timer", color: Palette.focus, title: "Flexible focus", detail: focus))
        if obstacles.contains("start") || obstacles.isEmpty || outcome == "start" {
            list.append(Preview(icon: "shoeprints.fill", color: Palette.tasks, title: "Tiny first steps",
                                detail: "Every task gets a first move small enough that starting feels easy."))
        }
        if obstacles.contains("comeback") || outcome == "calm" {
            list.append(Preview(icon: "arrow.uturn.backward.circle.fill", color: Palette.good, title: "Easy comebacks",
                                detail: "Missed a day? Your XP and level stay. You just pick up where you are."))
        }
        if obstacles.contains("routines") || outcome == "routines" {
            list.append(Preview(icon: "repeat", color: Palette.habits, title: "Small routines",
                                detail: "A few daily habits you check off in one tap."))
        }
        if reminder != "none" {
            let when = ["morning": "9:00 AM", "afternoon": "3:00 PM", "evening": "7:30 PM"][reminder] ?? "7:30 PM"
            list.append(Preview(icon: "bell.fill", color: Palette.spark, title: "One nudge a day",
                                detail: "A friendly reminder around \(when). Never a guilt trip."))
        }
        return list
    }

    // MARK: 5. First win

    private var firstWinStep: some View {
        StepPage(title: shrunk ? "Here's your first step" : "Let's get one small win",
                 subtitle: shrunk ? "Small enough that it barely feels like work. Edit it if you like."
                                  : "What's one thing you've been putting off?",
                 primary: shrunk ? "Start a 5-minute focus" : "Shrink it",
                 primaryDisabled: thing.trimmingCharacters(in: .whitespaces).isEmpty,
                 action: shrunk ? startFirstWin : shrink,
                 secondary: shrunk ? "Save it for later" : nil,
                 secondaryAction: saveForLater) {
            if !shrunk {
                BigField(placeholder: "Clean my room, study for the bio test…", text: $thing, onSubmit: shrink)
                    .transition(.opacity)
                HStack(spacing: 8) {
                    ForEach(["Reply to an email", "Start the essay", "Do the laundry"], id: \.self) { s in
                        Button {
                            thing = s
                            Haptics.shared.play(.tick)
                        } label: {
                            Text(s).font(.footnote.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .padding(.horizontal, 12).frame(height: 34)
                                .background(Palette.track, in: Capsule())
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(PressableStyle(scale: 0.94))
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label(thing, systemImage: "arrow.turn.down.right")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    BigField(placeholder: "The tiniest first move", text: $tiny, autofocus: false, onSubmit: {})
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.calm, value: shrunk)
    }

    private func shrink() {
        let t = thing.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        tiny = AppStore.tinyStep(for: t)
        withAnimation(.calm) { shrunk = true }
        Haptics.shared.play(.success)
        SoundFX.shared.play(.pop)
    }

    private func ensureTask() -> UUID? {
        if let taskID { store.setFirstStep(taskID, tiny); return taskID }
        let id = store.addTask(thing, firstStep: tiny)
        taskID = id
        return id
    }

    private func startFirstWin() {
        let id = ensureTask()
        finish()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            store.sessionRequest = SessionConfig(taskID: id, minutes: 5, quick: true)
        }
    }

    private func saveForLater() {
        _ = ensureTask()
        go(.plan)
    }

    // MARK: 6. First daily plan

    private var planStep: some View {
        let task = store.data.tasks.first { $0.id == taskID }
        let step = task?.firstStep ?? tiny
        return VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "Your next step", color: Palette.ember)
                Text("Let's get one thing moving.")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.4)
                VStack(alignment: .leading, spacing: 6) {
                    Text(step)
                        .font(.title3.weight(.semibold))
                        .contentTransition(.opacity)
                    if let task {
                        Label(task.title, systemImage: "arrow.turn.down.right")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .animation(.calm, value: step)
            }
            Spacer()
            VStack(spacing: 10) {
                Button {
                    finish()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        store.sessionRequest = SessionConfig(taskID: taskID, minutes: minutes, quick: true)
                    }
                } label: { Label("Start my first step", systemImage: "play.fill") }
                    .buttonStyle(GlowButtonStyle())
                HStack(spacing: 10) {
                    Button("Make it smaller") {
                        if let taskID { drawers.present { StepDrawer(taskID: taskID) } }
                    }
                    .buttonStyle(SoftButtonStyle())
                    Button("Not now") { finish() }
                        .buttonStyle(SoftButtonStyle(color: .secondary))
                }
                Button {
                    drawers.present { RescueDrawer(goToWork: {}) }
                    finish()
                } label: {
                    Label("I'm overwhelmed", systemImage: "hand.raised.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(height: 40)
                }
                .buttonStyle(PressableStyle(scale: 0.95))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    // MARK: Flow

    private func go(_ s: Step) {
        forward = s.rawValue > step.rawValue
        Haptics.shared.play(.light)
        withAnimation(.calm) { step = s }
    }

    private func skip() {
        finish()
    }

    private func finish() {
        var p = Personal()
        p.obstacles = Array(obstacles).sorted()
        p.outcome = outcome
        p.reminderSlot = reminder
        p.planHelp = planHelp
        store.data.personal = p
        store.data.defaultMinutes = minutes
        switch reminder {
        case "morning": store.data.reminderHour = 9; store.data.reminderMinute = 0
        case "afternoon": store.data.reminderHour = 15; store.data.reminderMinute = 0
        default: store.data.reminderHour = 19; store.data.reminderMinute = 30
        }
        store.data.lastActiveDay = store.today
        withAnimation(.easeInOut(duration: 0.45)) { store.data.onboarded = true }
        Haptics.shared.play(.success)
        if reminder != "none" {
            Notifier.requestAuthorization { _ in Notifier.reschedule(store) }
        }
        store.refresh()
    }
}

// MARK: - Pieces

private struct StepPage<Content: View>: View {
    let title: String
    let subtitle: String
    let primary: String
    var primaryDisabled = false
    let action: () -> Void
    var secondary: String? = nil
    var secondaryAction: () -> Void = {}
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.system(size: 30, weight: .bold))
                            .tracking(-0.4)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 10)
                    content()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            VStack(spacing: 4) {
                Button(primary, action: action)
                    .buttonStyle(GlowButtonStyle())
                    .disabled(primaryDisabled)
                if let secondary {
                    Button(secondary, action: secondaryAction)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(height: 44)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }
}

private struct OptionRow: View {
    let title: String
    let icon: String
    let selected: Bool
    let multi: Bool
    let toggle: () -> Void

    var body: some View {
        Button {
            withAnimation(.reward) { toggle() }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(selected ? Color.white : Palette.ember)
                    .frame(width: 38, height: 38)
                    .background(selected ? AnyShapeStyle(Palette.brand) : AnyShapeStyle(Palette.ember.opacity(0.12)),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : (multi ? "circle" : "circle"))
                    .font(.title3)
                    .foregroundStyle(selected ? Palette.ember : Color.secondary.opacity(0.4))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 64)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(selected ? Palette.ember.opacity(0.7) : .clear, lineWidth: 1.5))
            .scaleEffect(selected ? 1.0 : 0.995)
        }
        .buttonStyle(PressableStyle(haptic: .tick, scale: 0.97))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SegmentRow: View {
    let options: [(String, String)]
    @Binding var selection: String
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                let o = options[i]
                Button {
                    withAnimation(.calm) { selection = o.0 }
                } label: {
                    Text(o.1)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(selection == o.0 ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if selection == o.0 {
                                Capsule().fill(Palette.ember).matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                }
                .buttonStyle(PressableStyle(haptic: .tick, scale: 0.94))
                .accessibilityAddTraits(selection == o.0 ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Palette.card, in: Capsule())
    }
}

// MARK: - Permissions

private struct ProtectStep: View {
    @Environment(AppStore.self) private var store
    let next: () -> Void
    @State private var notifications: Bool? = nil
    @State private var mic: Bool? = VoiceRecorder.hasPermission ? true : nil

    var body: some View {
        StepPage(title: "Stay on track", subtitle: "Say yes to what helps. You can change this later in Settings.",
                 primary: "Continue", action: next) {
            PermissionCard(icon: "bell.badge.fill", color: Palette.ember, title: "Gentle reminders",
                           detail: "One nudge a day, and a heads-up when it's time to start something you planned.",
                           state: notifications, button: "Allow notifications") {
                Notifier.requestAuthorization { ok in withAnimation(.calm) { notifications = ok } }
            }

            PermissionCard(icon: "mic.fill", color: Palette.rose, title: "Brain dump by voice",
                           detail: "Hold a button and say everything on your mind. It's turned into tasks right on your phone.",
                           state: mic, button: "Allow microphone") {
                Task { @MainActor in
                    let ok = await VoiceRecorder.requestPermission()
                    withAnimation(.calm) { mic = ok }
                }
            }
        }
        .onAppear {
            UNUserNotificationCenter.current().getNotificationSettings { s in
                let ok = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
                DispatchQueue.main.async { if ok { notifications = true } else if s.authorizationStatus == .denied { notifications = false } }
            }
        }
    }
}

private struct PermissionCard: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String
    let state: Bool?
    let button: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.bold))
                    Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if state == true {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Palette.good)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            if state != true {
                Button(button, action: action)
                    .buttonStyle(SoftButtonStyle(color: color))
                    .disabled(state == false)
                    .opacity(state == false ? 0.5 : 1)
            }
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.reward, value: state)
    }
}

private struct PreviewCard: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.bold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
        .animation(.calm, value: detail)
    }
}

private struct BigField: View {
    let placeholder: String
    @Binding var text: String
    var autofocus = true
    let onSubmit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(1...3)
            .font(.title3.weight(.medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(focused ? Palette.ember.opacity(0.6) : .clear, lineWidth: 1.5))
            .focused($focused)
            .submitLabel(.go)
            .onChange(of: text) { _, new in
                if new.contains("\n") {
                    text = new.replacingOccurrences(of: "\n", with: "")
                    focused = false
                    onSubmit()
                }
            }
            .animation(.calm, value: focused)
            .onAppear { if autofocus { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { focused = true } } }
    }
}
