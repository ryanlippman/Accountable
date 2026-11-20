import SwiftUI

// Every prompt in the app: small bottom drawers instead of system alerts and sheets.
// They're presented through DrawerCenter (or a local Drawer inside full-screen views).

// MARK: - Make it smaller

struct StepDrawer: View {
    @Environment(AppStore.self) private var store
    @Environment(DrawerCenter.self) private var drawers
    let taskID: UUID
    @State private var text = ""

    private var task: WorkTask? { store.data.tasks.first { $0.id == taskID } }

    var body: some View {
        let title = task?.title ?? ""
        VStack(spacing: 14) {
            DrawerTitle(title: "Make it smaller",
                        message: "What's the tiniest first move for \u{201C}\(title)\u{201D}? Small enough that it feels almost silly.",
                        icon: "shoeprints.fill")
            DrawerField(placeholder: "Open the doc and write one sentence", text: $text, onSubmit: save)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions(for: title), id: \.self) { s in
                        Button {
                            text = s
                            Haptics.shared.play(.tick)
                        } label: {
                            Text(s)
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .background(text == s ? Palette.ember.opacity(0.16) : Palette.track, in: Capsule())
                                .foregroundStyle(text == s ? Palette.ember : Color.primary)
                        }
                        .buttonStyle(PressableStyle(scale: 0.94))
                    }
                }
            }
            .scrollClipDisabled()
            Button("Save first step", action: save)
                .buttonStyle(GlowButtonStyle())
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            Button {
                drawers.present { BreakdownDrawer(taskID: taskID) }
            } label: {
                Label("Break the whole thing into steps", systemImage: "list.bullet.indent")
            }
            .buttonStyle(SoftButtonStyle(color: Color(hex: 0x0D9488)))
        }
        .onAppear { text = task?.firstStep ?? "" }
    }

    private func suggestions(for title: String) -> [String] {
        var list = [AppStore.tinyStep(for: title), "Set a 2-minute timer and begin", "Write down what done looks like", "Gather what you need"]
        var seen = Set<String>()
        list = list.filter { seen.insert($0).inserted }
        return list
    }

    private func save() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        withAnimation(.calm) { store.setFirstStep(taskID, t) }
        Haptics.shared.play(.success)
        SoundFX.shared.play(.pop)
        drawers.dismiss()
    }
}

// MARK: - I'm overwhelmed

struct RescueDrawer: View {
    @Environment(AppStore.self) private var store
    @Environment(DrawerCenter.self) private var drawers
    var goToWork: () -> Void
    @State private var mode: Mode = .menu

    enum Mode { case menu, pick, breathe }

    var body: some View {
        ZStack {
            switch mode {
            case .menu: menu.transition(.blurReplace)
            case .pick: pick.transition(.blurReplace)
            case .breathe: BreatheView(done: { withAnimation(.calm) { mode = .menu } }).transition(.blurReplace)
            }
        }
        .animation(.calm, value: mode)
    }

    private var menu: some View {
        VStack(spacing: 10) {
            DrawerTitle(title: "Let's make this lighter",
                        message: "You don't have to do everything. Just pick one way in.",
                        icon: "hand.raised.fill", iconColor: Palette.habits)
            option("5 minutes on the next thing", "Tiny, then you can stop.", "timer", Palette.focus) {
                drawers.dismiss()
                store.sessionRequest = SessionConfig(taskID: store.upNext?.id, minutes: 5, quick: true)
            }
            if store.openTasks.count > 1 {
                option("Pick just one", "Everything else can wait.", "scope", Palette.ember) {
                    withAnimation(.calm) { mode = .pick }
                }
            }
            option("Empty your head", "Say it all out loud. It gets sorted for you.", "mic.fill", Palette.tasks) {
                drawers.dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { store.showBrainDump = true }
            }
            option("Breathe for a minute", "Slow in, slower out.", "wind", Palette.habits) {
                withAnimation(.calm) { mode = .breathe }
            }
        }
    }

    private var pick: some View {
        VStack(spacing: 10) {
            DrawerTitle(title: "Pick just one", message: "It becomes today's one thing. The rest can wait.", icon: "scope")
            ForEach(store.openTasks.prefix(4)) { t in
                Button {
                    store.setPledge(t.title)
                    Haptics.shared.play(.success)
                    SoundFX.shared.play(.pop)
                    drawers.dismiss()
                } label: {
                    HStack {
                        Text(t.title).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .background(Palette.track, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressableStyle(scale: 0.98))
            }
            Button("Back") { withAnimation(.calm) { mode = .menu } }
                .buttonStyle(SoftButtonStyle(color: .secondary))
        }
    }

    private func option(_ title: String, _ detail: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 60)
            .background(Palette.track, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }
}

/// Six slow breaths: 4 seconds in, 6 out. A soft haptic marks each turn.
private struct BreatheView: View {
    var done: () -> Void
    @State private var start = Date()
    @State private var lastPhase = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            let cycle = t.truncatingRemainder(dividingBy: 10)
            let inhale = cycle < 4
            let x = inhale ? cycle / 4 : 1 - (cycle - 4) / 6
            let eased = 0.5 - cos(x * .pi) / 2
            let breaths = Int(t / 10)
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Palette.habits.opacity(0.12))
                    Circle()
                        .fill(Palette.habits.gradient)
                        .scaleEffect(reduceMotion ? 0.8 : 0.45 + 0.55 * eased)
                        .opacity(reduceMotion ? 0.35 + 0.65 * eased : 1)
                }
                .frame(width: 180, height: 180)
                Text(breaths >= 6 ? "Nice. Ready when you are." : (inhale ? "Breathe in" : "Breathe out"))
                    .font(.title3.weight(.semibold))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: inhale)
                Button(breaths >= 6 ? "Done" : "I'm good") { done() }
                    .buttonStyle(SoftButtonStyle(color: Palette.habits))
            }
            .onChange(of: inhale) { _, _ in Haptics.shared.play(.soft) }
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Breathing exercise. Breathe in for four seconds, out for six.")
    }
}

// MARK: - Plan a start

struct PlanDrawer: View {
    @Environment(AppStore.self) private var store
    @Environment(DrawerCenter.self) private var drawers
    let taskID: UUID
    @State private var date = Date()
    @State private var choice: String? = nil

    private var task: WorkTask? { store.data.tasks.first { $0.id == taskID } }

    var body: some View {
        VStack(spacing: 14) {
            DrawerTitle(title: "When will you start?",
                        message: "Start within 15 minutes for +15 XP. You'll get a nudge first.",
                        icon: "alarm.fill", iconColor: Palette.habits)
            HStack(spacing: 8) {
                chip("In 15 min", Date().addingTimeInterval(15 * 60))
                chip("Tonight", at(19, 30, 0))
                chip("Tomorrow", at(16, 0, 1))
            }
            DatePicker("Start", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .font(.body.weight(.medium))
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(Palette.track, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onChange(of: date) { _, _ in choice = nil }
            Button("Plan it") {
                store.planTask(taskID, at: date)
                Notifier.requestAuthorization { _ in Notifier.reschedule(store) }
                Haptics.shared.play(.success)
                SoundFX.shared.play(.pop)
                drawers.dismiss()
            }
            .buttonStyle(GlowButtonStyle(tint: Palette.habits))
            if task?.plannedStart != nil {
                Button("Clear start time") {
                    store.planTask(taskID, at: nil)
                    Haptics.shared.play(.light)
                    drawers.dismiss()
                }
                .buttonStyle(SoftButtonStyle(color: Palette.bad))
            }
        }
        .onAppear { date = task?.plannedStart ?? at(19, 30, 0) }
    }

    private func chip(_ label: String, _ d: Date) -> some View {
        Button {
            withAnimation(.calm) { date = d }
            DispatchQueue.main.async { choice = label }
            Haptics.shared.play(.tick)
        } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(choice == label ? Palette.habits.opacity(0.16) : Palette.track, in: Capsule())
                .foregroundStyle(choice == label ? Palette.habits : Color.primary)
        }
        .buttonStyle(PressableStyle(scale: 0.94))
    }

    private func at(_ hour: Int, _ minute: Int, _ dayOffset: Int) -> Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        let d = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? Date()
        return d < Date() ? (cal.date(byAdding: .day, value: 1, to: d) ?? d) : d
    }
}

// MARK: - Rename

struct RenameDrawer: View {
    @Environment(AppStore.self) private var store
    @Environment(DrawerCenter.self) private var drawers
    let taskID: UUID
    @State private var text = ""

    var body: some View {
        VStack(spacing: 14) {
            DrawerTitle(title: "Rename task")
            DrawerField(placeholder: "Task name", text: $text, onSubmit: save)
            Button("Save", action: save)
                .buttonStyle(GlowButtonStyle())
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear { text = store.data.tasks.first { $0.id == taskID }?.title ?? "" }
    }

    private func save() {
        store.renameTask(taskID, text)
        Haptics.shared.play(.medium)
        drawers.dismiss()
    }
}

// MARK: - Confirm (destructive or important choices)

struct ConfirmPrompt: View {
    let title: String
    var message: String? = nil
    var icon: String = "exclamationmark.triangle.fill"
    var color: Color = Palette.bad
    let confirm: String
    var cancel: String = "Cancel"
    var dark = false
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            DrawerTitle(title: title, message: message, icon: icon, iconColor: color)
            Button(confirm, action: onConfirm)
                .buttonStyle(GlowButtonStyle(tint: color))
            Button(cancel, action: onCancel)
                .buttonStyle(SoftButtonStyle(color: .secondary, dark: dark))
        }
    }
}

// MARK: - Streak

struct StreakDrawer: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(store.streak)")
                        .font(.system(size: 60, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    Text(store.streak == 1 ? "day streak" : "day streak").font(.headline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "flame.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(store.doneToday ? AnyShapeStyle(Palette.brand) : AnyShapeStyle(Palette.track))
                    .symbolEffect(.bounce, value: store.streak)
            }
            Text(store.doneToday ? "Today counts. See you tomorrow." : "Any focus session today keeps it going, even 5 minutes.")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            MonthGrid()
            HStack(spacing: 10) {
                Pill(icon: "snowflake", color: Palette.shield, text: "\(store.data.freezes)/2 freezes")
                Pill(icon: "trophy.fill", color: Palette.xp, text: "Best \(store.data.bestStreak)")
                let next = [3, 7, 14, 21, 30, 50, 75, 100, 150, 200, 250, 300, 365, 500, 1000].first(where: { $0 > store.streak }) ?? 1000
                Pill(icon: "flag.checkered", color: Palette.ember, text: "Next \(next)")
            }
        }
    }
}

private struct Pill: View {
    let icon: String
    let color: Color
    let text: String
    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct MonthGrid: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let count = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        let lead = (cal.component(.weekday, from: start) + 5) % 7
        let cells: [Int?] = Array(repeating: nil, count: lead) + (1...count).map { Optional($0) }
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        VStack(alignment: .leading, spacing: 8) {
            Text(now.formatted(.dateTime.month(.wide).year())).font(.subheadline.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(letters.indices, id: \.self) { i in
                    Text(letters[i]).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                }
                ForEach(cells.indices, id: \.self) { i in
                    if let d = cells[i] {
                        let date = cal.date(byAdding: .day, value: d - 1, to: start) ?? start
                        let log = store.log(date.dayKey)
                        ZStack {
                            Circle().fill(log.sessions > 0 ? AnyShapeStyle(Palette.brand) : AnyShapeStyle(log.frozen ? Palette.shield.opacity(0.3) : Color.clear))
                            if cal.isDateInToday(date) { Circle().stroke(Palette.ember, lineWidth: 1.5) }
                            Text("\(d)").font(.caption.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(log.sessions > 0 ? Color.white : (date > now ? Color.secondary : Color.primary))
                        }
                        .frame(height: 30)
                    } else {
                        Color.clear.frame(height: 30)
                    }
                }
            }
        }
        .padding(14)
        .background(Palette.track.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Shields

struct ShieldsDrawer: View {
    @Environment(AppStore.self) private var store
    @Environment(DrawerCenter.self) private var drawers
    @State private var failed = 0

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: i < store.data.shields ? "shield.lefthalf.filled" : "shield")
                        .font(.system(size: 34))
                        .foregroundStyle(i < store.data.shields ? Palette.shield : Color.secondary.opacity(0.35))
                        .symbolEffect(.bounce, value: store.data.shields)
                }
            }
            .modifier(Shake(amount: CGFloat(failed)))
            .padding(.top, 4)
            Text(store.data.shields == 0
                 ? "Out of shields, so sessions earn half XP for now. A short recovery session wins one back."
                 : "Shields protect your XP. Leaving the app mid-focus or missing a planned start cracks one. One comes back each day.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                drawers.dismiss()
                store.sessionRequest = SessionConfig(taskID: nil, minutes: 5, recovery: true)
            } label: {
                Label("5-minute recovery session", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(GlowButtonStyle(theme: TimerTheme.find(store.data.theme)))
            .disabled(store.data.shields >= 5)
            Button {
                if store.buy(.refill) {
                    Haptics.shared.sparkle(); SoundFX.shared.play(.purchase); store.confetti += 1
                } else {
                    withAnimation(.linear(duration: 0.4)) { failed += 1 }
                    Haptics.shared.play(.error); SoundFX.shared.play(.error)
                }
            } label: {
                Label("Refill for \(store.price(.refill)) sparks", systemImage: "sparkle")
            }
            .buttonStyle(SoftButtonStyle(color: Palette.spark))
            .disabled(store.data.shields >= 5)
        }
    }
}

struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(amount * .pi * 4), y: 0))
    }
}
