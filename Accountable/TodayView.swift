import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(DrawerCenter.self) private var drawers
    var goToFocus: () -> Void
    var goToWork: () -> Void
    @State private var selected = DayKey.today

    private var isToday: Bool { selected == store.today }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                WeekPager(selected: $selected)
                DayHeader(selected: $selected)

                if isToday {
                    StreakRisk()
                        .transition(.opacity)
                    Launchpad(goToWork: goToWork)
                        .riseIn(0.05)
                        .transition(.opacity)
                }
                DayHero(day: selected)
                    .riseIn(0.12)
                    .scrollEdgeFade()
                if isToday {
                    PledgeCard().riseIn(0.2).scrollEdgeFade().transition(.opacity)
                    HabitsCard().riseIn(0.26).scrollEdgeFade().transition(.opacity)
                    QuestsCard().riseIn(0.32).scrollEdgeFade().transition(.opacity)
                } else {
                    DaySummary(day: selected)
                        .scrollEdgeFade()
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
            .animation(.calm, value: isToday)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { AppBackground() }
        // The title never changes, so nothing in the navigation bar jumps when you pick another day.
        .navigationTitle("Today")
        .onAppear { if selected > store.today { selected = store.today } }
    }
}

// MARK: - Week pager

/// One page per week, newest on the right. Native paging gives real momentum and rubber-banding;
/// the selection pill glides between days with a matched geometry effect.
private struct WeekPager: View {
    @Environment(AppStore.self) private var store
    @Binding var selected: String
    @State private var page: Int? = 0
    @Namespace private var pill

    private let weeks = Array((-11...0))

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(weeks, id: \.self) { w in
                    WeekRow(monday: DayKey.add(AppStore.mondayOfWeek(store.today), w * 7), selected: $selected, pill: pill)
                        .containerRelativeFrame(.horizontal)
                        .id(w)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .defaultScrollAnchor(.trailing)
        .frame(height: 84)
        .onChange(of: page) { _, w in
            guard let w else { return }
            // Keep the same weekday when paging, but never land in the future.
            let monday = AppStore.mondayOfWeek(store.today)
            let wd = dayIndex(selected)
            let k = min(DayKey.add(monday, w * 7 + wd), store.today)
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { selected = k }
            Haptics.shared.play(.tick)
        }
        .onChange(of: selected) { _, k in
            let w = weekOffset(of: k)
            if w != page { withAnimation(.calm) { page = w } }
        }
    }

    private func dayIndex(_ k: String) -> Int {
        let d = DayKey.date(k) ?? Date()
        return (Calendar(identifier: .gregorian).component(.weekday, from: d) + 5) % 7
    }

    private func weekOffset(of k: String) -> Int {
        let a = DayKey.date(AppStore.mondayOfWeek(store.today)) ?? Date()
        let b = DayKey.date(AppStore.mondayOfWeek(k)) ?? Date()
        let days = Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
        return Int((Double(days) / 7).rounded())
    }
}

private struct WeekRow: View {
    @Environment(AppStore.self) private var store
    let monday: String
    @Binding var selected: String
    let pill: Namespace.ID

    var body: some View {
        let today = store.today
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                let k = DayKey.add(monday, i)
                DayCell(day: k, isToday: k == today, isSelected: k == selected, future: k > today, pill: pill) {
                    withAnimation(.calm) { selected = k }
                }
            }
        }
        .padding(.horizontal, 2)
    }
}

private struct DayCell: View {
    @Environment(AppStore.self) private var store
    let day: String
    let isToday: Bool
    let isSelected: Bool
    let future: Bool
    let pill: Namespace.ID
    let action: () -> Void

    var body: some View {
        let date = DayKey.date(day) ?? Date()
        let sc = store.score(day)
        let log = store.log(day)
        let has = log.sessions > 0 || log.xp > 0
        Button(action: action) {
            VStack(spacing: 5) {
                Text(date.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isToday ? Palette.ember : Color.secondary)
                ZStack {
                    Ring(progress: future ? 0 : Double(sc.total) / 100, lineWidth: 3.5,
                         color: isToday ? Palette.ember : .primary, dashedWhenEmpty: !has)
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                    if log.frozen {
                        Image(systemName: "snowflake")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Palette.shield)
                            .offset(y: 16)
                    }
                }
                .frame(width: 38, height: 38)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Palette.card)
                        .shadow(color: .black.opacity(0.07), radius: 8, y: 3)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
        }
        .buttonStyle(PressableStyle(haptic: .tick, scale: 0.94))
        .disabled(future)
        .opacity(future ? 0.35 : 1)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month().day()) + (future ? "" : ", score \(sc.total)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A fixed-height line under the week strip. Its text cross-fades instead of the layout moving.
private struct DayHeader: View {
    @Environment(AppStore.self) private var store
    @Binding var selected: String

    var body: some View {
        let isToday = selected == store.today
        let date = DayKey.date(selected) ?? Date()
        HStack {
            Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .id(selected)
                .transition(.opacity)
            Spacer()
            if !isToday {
                Button {
                    withAnimation(.calm) { selected = store.today }
                } label: {
                    Label("Today", systemImage: "arrow.uturn.forward")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Palette.ember.opacity(0.12), in: Capsule())
                        .foregroundStyle(Palette.ember)
                }
                .buttonStyle(PressableStyle(scale: 0.92))
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 4)
        .animation(.calm, value: selected)
    }
}

// MARK: - Launchpad ("Your next step")

private struct Launchpad: View {
    @Environment(AppStore.self) private var store
    @Environment(DrawerCenter.self) private var drawers
    var goToWork: () -> Void
    @State private var skipped: [UUID] = []
    @State private var direction: Edge = .trailing
    @State private var newThing = ""
    @FocusState private var typing: Bool

    private var candidates: [WorkTask] {
        var list: [WorkTask] = []
        if let n = store.upNext { list.append(n) }
        for t in store.openTasks where !list.contains(where: { $0.id == t.id }) { list.append(t) }
        return list
    }

    var body: some View {
        let all = candidates
        let task = all.first { !skipped.contains($0.id) }
        let due = task.map { store.isDue($0) } ?? false
        let theme = TimerTheme.find(store.data.theme)

        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: due ? "Time to start" : "Your next step", color: due ? Color.white.opacity(0.85) : Palette.ember)
                .padding(.bottom, 8)

            ZStack(alignment: .topLeading) {
                if let task {
                    TaskLaunch(task: task, due: due, theme: theme, skip: { skip(task) })
                        .id(task.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: direction).combined(with: .opacity),
                            removal: .move(edge: direction == .trailing ? .leading : .trailing).combined(with: .opacity)))
                } else if !all.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("That's everything for now.").font(.title3.weight(.bold))
                        Text("Want to look again? Sometimes the second look is easier.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Show my tasks again") {
                            direction = .leading
                            withAnimation(.calm) { skipped = [] }
                        }
                        .buttonStyle(SoftButtonStyle())
                    }
                    .transition(.opacity)
                } else {
                    emptyState
                        .transition(.opacity)
                }
            }
            .clipped()

            if !due {
                HStack(spacing: 0) {
                    if store.openTasks.count >= 2 {
                        Button {
                            drawers.present { PickForMeDrawer() }
                        } label: {
                            Label("Pick for me", systemImage: "dice.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                        }
                        .buttonStyle(PressableStyle(scale: 0.95))
                        Divider().frame(height: 18)
                    }
                    Button {
                        drawers.present { RescueDrawer(goToWork: goToWork) }
                    } label: {
                        Label("I'm overwhelmed", systemImage: "hand.raised.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    .buttonStyle(PressableStyle(scale: 0.95))
                }
                .padding(.top, 10)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(due ? AnyShapeStyle(theme.gradient) : AnyShapeStyle(Palette.card))
                .shadow(color: due ? theme.c2.opacity(0.35) : .clear, radius: 20, y: 10)
        }
        .animation(.calm, value: task?.id)
        .animation(.calm, value: due)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Let's get one thing moving.").font(.title2.weight(.bold))
            Text("What's one thing on your mind? We'll shrink it to a first step.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button {
                store.showBrainDump = true
            } label: {
                Label("Or just say everything", systemImage: "mic.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ember)
            }
            .buttonStyle(PressableStyle(scale: 0.96))
            HStack(spacing: 10) {
                TextField("Finish the history essay", text: $newThing)
                    .focused($typing)
                    .submitLabel(.go)
                    .onSubmit(add)
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(Palette.track, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Button(action: add) {
                    Image(systemName: "arrow.up")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Palette.brand, in: Circle())
                }
                .buttonStyle(PressableStyle(haptic: .medium, scale: 0.9))
                .disabled(newThing.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(newThing.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                .accessibilityLabel("Add")
            }
        }
    }

    private func add() {
        let t = newThing.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        direction = .trailing
        withAnimation(.calm) { store.addTask(t, firstStep: AppStore.tinyStep(for: t)) }
        newThing = ""
        typing = false
        Haptics.shared.play(.success)
        SoundFX.shared.play(.pop)
    }

    private func skip(_ t: WorkTask) {
        direction = .trailing
        withAnimation(.calm) { skipped.append(t.id) }
    }
}

private struct TaskLaunch: View {
    @Environment(AppStore.self) private var store
    @Environment(DrawerCenter.self) private var drawers
    let task: WorkTask
    let due: Bool
    let theme: TimerTheme
    let skip: () -> Void

    var body: some View {
        let next = task.steps.first(where: { !$0.done })
        let step = task.nextAction ?? AppStore.tinyStep(for: task.title)
        let doneSteps = task.steps.filter(\.done).count
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                if !task.steps.isEmpty {
                    HStack(spacing: 8) {
                        Text("STEP \(min(doneSteps + 1, task.steps.count)) OF \(task.steps.count)")
                            .font(.caption2.weight(.heavy))
                            .tracking(0.6)
                            .foregroundStyle(due ? Color.white.opacity(0.85) : Color(hex: 0x0D9488))
                            .contentTransition(.numericText(value: Double(doneSteps)))
                        HStack(spacing: 3) {
                            ForEach(task.steps) { s in
                                Capsule()
                                    .fill(s.done ? (due ? Color.white : Color(hex: 0x0D9488)) : (due ? Color.white.opacity(0.25) : Palette.track))
                                    .frame(height: 4)
                            }
                        }
                    }
                }
                HStack(alignment: .top, spacing: 10) {
                    Text(step)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(due ? Color.white : Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                    Spacer(minLength: 0)
                    if let next {
                        Button {
                            withAnimation(.reward) { store.toggleStep(task.id, next.id) }
                            Haptics.shared.play(.success)
                            SoundFX.shared.play(.xp)
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(due ? Color.black : Color.white)
                                .frame(width: 38, height: 38)
                                .background(due ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color(hex: 0x0D9488)), in: Circle())
                        }
                        .buttonStyle(PressableStyle(haptic: .none, scale: 0.86))
                        .accessibilityLabel("Step done")
                    }
                }
                .animation(.calm, value: step)
                HStack(spacing: 10) {
                    Label(task.title, systemImage: "arrow.turn.down.right")
                        .lineLimit(1)
                    if let at = task.plannedStart {
                        Label(at.formatted(date: .omitted, time: .shortened), systemImage: "alarm")
                            .fixedSize()
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(due ? Color.white.opacity(0.85) : Color.secondary)
            }

            Button {
                store.sessionRequest = SessionConfig(taskID: task.id, minutes: store.data.defaultMinutes)
            } label: {
                Label("Start my first step", systemImage: "play.fill")
            }
            .buttonStyle(GlowButtonStyle(theme: theme, dark: due))

            HStack(spacing: 10) {
                Button(task.steps.isEmpty ? "Make it smaller" : "Steps") {
                    if task.steps.isEmpty {
                        drawers.present { StepDrawer(taskID: task.id) }
                    } else {
                        drawers.present { BreakdownDrawer(taskID: task.id) }
                    }
                }
                .buttonStyle(SoftButtonStyle(color: Palette.ember, dark: due))
                Button("Not now", action: skip)
                    .buttonStyle(SoftButtonStyle(color: .secondary, dark: due))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Streak risk (supportive, never a threat)

private struct StreakRisk: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let hour = Calendar.current.component(.hour, from: ctx.date)
            if store.streak > 0 && !store.doneToday && hour >= 16 {
                HStack(spacing: 12) {
                    Image(systemName: "flame.fill")
                        .font(.title2)
                        .foregroundStyle(Palette.brand)
                        .symbolEffect(.pulse, options: .repeating.speed(0.5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Still time for today").font(.subheadline.weight(.bold))
                        Text("A 5-minute session keeps your \(store.streak)-day streak going.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        store.sessionRequest = SessionConfig(taskID: store.upNext?.id, minutes: 5, quick: true)
                    } label: {
                        Text("5 min")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(Palette.brand, in: Capsule())
                    }
                    .buttonStyle(PressableStyle(haptic: .medium, scale: 0.92))
                }
                .padding(14)
                .background(Palette.ember.opacity(0.1), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }
}

// MARK: - Pledge

private struct PledgeCard: View {
    @Environment(AppStore.self) private var store
    @State private var text = ""
    @FocusState private var typing: Bool

    var body: some View {
        let log = store.todayLog
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Today's one thing")
            if log.pledge.isEmpty {
                HStack(spacing: 10) {
                    TextField("If I only get one thing done today…", text: $text)
                        .focused($typing)
                        .submitLabel(.done)
                        .onSubmit(commit)
                    Button(action: commit) {
                        Text("Commit")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(Palette.ember, in: Capsule())
                    }
                    .buttonStyle(PressableStyle(haptic: .medium, scale: 0.92))
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(text.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                }
                .transition(.opacity)
            } else {
                HStack(spacing: 12) {
                    Button {
                        if log.pledgeDone { store.undoPledge() } else {
                            store.completePledge()
                            store.confetti += 1
                        }
                    } label: {
                        Image(systemName: log.pledgeDone ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 28))
                            .foregroundStyle(log.pledgeDone ? Palette.good : Color.secondary)
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: log.pledgeDone)
                    }
                    .buttonStyle(PressableStyle(haptic: .medium, scale: 0.85))
                    .accessibilityLabel(log.pledgeDone ? "Undo" : "Mark done")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(log.pledge)
                            .font(.headline)
                            .strikethrough(log.pledgeDone, color: Palette.good)
                            .foregroundStyle(log.pledgeDone ? Color.secondary : Color.primary)
                        Text(log.pledgeDone ? "+50 XP banked" : "Worth +50 XP")
                            .font(.caption).foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                    }
                    Spacer(minLength: 8)
                    if !log.pledgeDone {
                        Button {
                            text = log.pledge
                            store.setPledge("")
                            typing = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, height: 34)
                                .background(Palette.track, in: Circle())
                        }
                        .buttonStyle(PressableStyle(scale: 0.9))
                        .accessibilityLabel("Change")
                    }
                }
                .transition(.opacity)
            }
        }
        .card()
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Palette.good.opacity(log.pledgeDone ? 0.08 : 0))
                .allowsHitTesting(false)
        }
        .animation(.calm, value: log.pledgeDone)
        .animation(.calm, value: log.pledge.isEmpty)
    }

    private func commit() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.setPledge(text)
        text = ""
        typing = false
        Haptics.shared.play(.medium)
        SoundFX.shared.play(.pop)
    }
}

// MARK: - Habits (checked right here, added inline)

struct HabitsCard: View {
    @Environment(AppStore.self) private var store
    @State private var adding = false
    @State private var title = ""
    @FocusState private var typing: Bool

    var body: some View {
        let habits = store.data.habits
        let done = habits.filter { store.habitDone($0) }.count
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow(text: "Habits")
                Spacer()
                if !habits.isEmpty {
                    Text("\(done) of \(habits.count)")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
                        .contentTransition(.numericText(value: Double(done)))
                }
            }
            ForEach(habits) { h in
                HabitLine(habit: h)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            }
            if adding || habits.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Palette.habits)
                    TextField(habits.isEmpty ? "Add a small daily habit" : "Another habit", text: $title)
                        .focused($typing)
                        .submitLabel(.done)
                        .onSubmit(add)
                }
                .transition(.opacity)
            } else {
                Button {
                    withAnimation(.calm) { adding = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { typing = true }
                } label: {
                    Label("Add a habit", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.habits)
                }
                .buttonStyle(PressableStyle(scale: 0.95))
            }
        }
        .card()
        .animation(.calm, value: habits.map(\.id))
        .onChange(of: typing) { _, now in
            if !now && title.isEmpty { withAnimation(.calm) { adding = false } }
        }
    }

    private func add() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { typing = false; return }
        withAnimation(.calm) { store.addHabit(t) }
        title = ""
        typing = true
        Haptics.shared.play(.medium)
        SoundFX.shared.play(.pop)
    }
}

struct HabitLine: View {
    @Environment(AppStore.self) private var store
    let habit: Habit

    var body: some View {
        let done = store.habitDone(habit)
        let streak = store.habitStreak(habit)
        Button {
            withAnimation(.reward) { store.toggleHabit(habit) }
            if store.habitDone(habit) {
                Haptics.shared.play(.success)
                SoundFX.shared.play(.xp)
            }
        } label: {
            HStack(spacing: 12) {
                CheckCircle(on: done, color: Palette.habits, size: 26)
                Text(habit.title)
                    .foregroundStyle(done ? Color.secondary : Color.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 6)
                if streak > 0 {
                    Label("\(streak)", systemImage: "flame.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.ember)
                        .contentTransition(.numericText(value: Double(streak)))
                }
                Text("+5")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(done ? Palette.habits : Color.secondary.opacity(0.6))
            }
            .frame(minHeight: 36)
        }
        .buttonStyle(PressableStyle(haptic: .light, scale: 0.98))
        .accessibilityLabel(habit.title)
        .accessibilityValue(done ? "Done" : "Not done")
    }
}

// MARK: - Focus score

private struct ScoreHero: View {
    @Environment(AppStore.self) private var store
    let day: String

    var body: some View {
        let sc = store.score(day)
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Focus score")
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(sc.total)")
                        .font(.system(size: 54, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(sc.total)))
                    Text("/100").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text("7-day average \(store.weekAverage)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            ZStack {
                ScoreRing(score: sc, lineWidth: 12)
                VStack(spacing: 0) {
                    Text("\(store.log(day).xp)")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(store.log(day).xp)))
                    Text("XP").font(.caption2.weight(.heavy)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 104, height: 104)
        }
        .card(20)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Palette.ember.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .center))
                .allowsHitTesting(false)
        }
        .animation(.calm, value: day)
        .accessibilityElement(children: .combine)
    }
}

private struct Minis: View {
    @Environment(AppStore.self) private var store
    let day: String

    var body: some View {
        let sc = store.score(day)
        let log = store.log(day)
        let habitsDone = store.data.habits.filter { log.habits.contains($0.id) }.count
        HStack(spacing: 10) {
            Mini(value: sc.tasks, max: 45, label: log.tasksDone == 1 ? "1 task done" : "\(log.tasksDone) tasks done",
                 fraction: sc.tasksFraction, color: Palette.tasks)
            Mini(value: sc.focus, max: 30, label: "\(log.focusMinutes) min focused", fraction: sc.focusFraction, color: Palette.focus)
            Mini(value: sc.habits, max: 25, label: store.data.habits.isEmpty ? "Showed up" : "\(habitsDone) of \(store.data.habits.count) habits",
                 fraction: sc.habitsFraction, color: Palette.habits)
        }
        .animation(.calm, value: day)
    }
}

private struct Mini: View {
    let value: Int
    let max: Int
    let label: String
    let fraction: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(value)").font(.system(.title2, design: .rounded).weight(.heavy)).foregroundStyle(color)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(value)))
                Text("/\(max)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            Ring(progress: fraction, lineWidth: 6, color: color, dashedWhenEmpty: true)
                .frame(width: 48, height: 48)
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// For a past day: what happened, plainly.
private struct DaySummary: View {
    @Environment(AppStore.self) private var store
    let day: String

    var body: some View {
        let log = store.log(day)
        let habits = store.data.habits.filter { log.habits.contains($0.id) }
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "That day")
            if log.sessions == 0 && log.tasksDone == 0 && habits.isEmpty && !log.frozen {
                Text("A rest day. That's allowed.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                if log.frozen && log.sessions == 0 {
                    row("snowflake", Palette.shield, "Streak freeze covered this day")
                }
                if log.sessions > 0 {
                    row("timer", Palette.focus, "\(log.sessions) session\(log.sessions == 1 ? "" : "s") · \(log.focusMinutes) min")
                }
                if log.tasksDone > 0 {
                    row("checkmark.seal.fill", Palette.tasks, "\(log.tasksDone) task\(log.tasksDone == 1 ? "" : "s") finished")
                }
                if !log.pledge.isEmpty {
                    row(log.pledgeDone ? "scope" : "circle.dashed", Palette.ember, log.pledge)
                }
                ForEach(habits) { h in row("repeat", Palette.habits, h.title) }
                if log.maxCombo > 0 { row("flame.fill", Palette.ember, "Best combo ×\(log.maxCombo)") }
            }
        }
        .card()
    }

    private func row(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 24)
            Text(text).font(.subheadline)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Quests

struct QuestsCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let qs = store.todayQuests
        let chest = store.todayLog.chest
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Daily quests").font(.headline)
                Spacer()
                TimelineView(.periodic(from: .now, by: 60)) { ctx in
                    let end = Calendar.current.startOfDay(for: ctx.date).addingTimeInterval(86_400)
                    let s = Int(end.timeIntervalSince(ctx.date))
                    Text("New in \(s / 3600)h \(s % 3600 / 60)m").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            ForEach(qs) { q in QuestRow(quest: q) }
            Divider()
            HStack(spacing: 12) {
                Image(systemName: chest ? "gift.fill" : "gift")
                    .font(.title2)
                    .foregroundStyle(chest ? AnyShapeStyle(Palette.brand) : AnyShapeStyle(Color.secondary))
                    .symbolEffect(.bounce, value: chest)
                VStack(alignment: .leading, spacing: 1) {
                    Text(chest ? "Bonus claimed" : "Bonus chest").font(.subheadline.weight(.semibold))
                    Text(chest ? "New quests at midnight." : "All three: +30 sparks and 15 min of double XP.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }
}

struct QuestRow: View {
    let quest: Quest

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: quest.done ? "checkmark.circle.fill" : quest.icon)
                .font(.title3)
                .foregroundStyle(quest.done ? Palette.good : Palette.ember)
                .frame(width: 28)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(quest.title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(min(quest.progress, quest.target))/\(quest.target)")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
                        .contentTransition(.numericText(value: Double(quest.progress)))
                }
                Bar(value: quest.fraction, color: quest.done ? Palette.good : Palette.ember, height: 7)
            }
            HStack(spacing: 2) {
                Image(systemName: "sparkle")
                Text("\(quest.sparks)")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(quest.done ? Color.secondary : Palette.spark)
            .frame(width: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
