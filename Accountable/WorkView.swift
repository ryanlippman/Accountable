import SwiftUI

struct WorkView: View {
    @Environment(AppStore.self) private var store
    @Environment(DrawerCenter.self) private var drawers
    @State private var newTitle = ""
    @State private var habitTitle = ""
    @State private var finishing: Set<UUID> = []
    @State private var showFinished = false
    @FocusState private var focus: Field?

    enum Field { case task, habit }

    var body: some View {
        List {
            Section {
                InlineAdd(placeholder: "Add a task, essay, problem set…", color: Palette.ember,
                          text: $newTitle, focus: $focus, field: .task, onSubmit: addTask,
                          onMic: { store.dumpStart = .voice; store.showBrainDump = true },
                          onScan: { store.dumpStart = DocumentScanner.isAvailable ? .scan : .photos; store.showBrainDump = true })

                ForEach(store.openTasks) { t in
                    TaskRow(task: t, finishing: finishing.contains(t.id)) { finish(t) }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { finish(t) } label: { Label("Finish", systemImage: "checkmark") }
                                .tint(Palette.good)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { withAnimation(.calm) { store.deleteTask(t.id) } } label: { Label("Delete", systemImage: "trash") }
                            Button { drawers.present { PlanDrawer(taskID: t.id) } } label: { Label("Plan", systemImage: "alarm") }
                                .tint(Palette.habits)
                        }
                        .contextMenu {
                            Button { drawers.present { BreakdownDrawer(taskID: t.id) } } label: { Label("Break it down", systemImage: "list.bullet.indent") }
                            Button { drawers.present { StepDrawer(taskID: t.id) } } label: { Label("Make it smaller", systemImage: "shoeprints.fill") }
                            Button { drawers.present { PlanDrawer(taskID: t.id) } } label: { Label("Plan a start", systemImage: "alarm") }
                            Button { drawers.present { RenameDrawer(taskID: t.id) } } label: { Label("Rename", systemImage: "pencil") }
                            Button(role: .destructive) { withAnimation(.calm) { store.deleteTask(t.id) } } label: { Label("Delete", systemImage: "trash") }
                        }
                }
            } header: {
                HStack {
                    Text("To do")
                    Spacer()
                    if store.openTasks.count >= 2 {
                        Button {
                            drawers.present { PickForMeDrawer() }
                        } label: {
                            Label("Pick for me", systemImage: "dice.fill")
                                .font(.caption.weight(.bold))
                                .textCase(nil)
                        }
                        .buttonStyle(PressableStyle(scale: 0.92))
                        .foregroundStyle(Palette.spark)
                    }
                }
            } footer: {
                // The empty state lives under the card, not inside it, so the add row keeps its rounded corners.
                if store.openTasks.isEmpty {
                    EmptyStateView(icon: store.finishedTasks.isEmpty ? "sparkles" : "checkmark.seal.fill",
                                   title: store.finishedTasks.isEmpty ? "Nothing here yet" : "All clear",
                                   message: store.finishedTasks.isEmpty
                                       ? "Type a task above, or say everything on your mind and it gets sorted into steps."
                                       : "Every task is done. Add the next one when it shows up.",
                                   actionTitle: "Brain dump",
                                   action: { store.dumpStart = .voice; store.showBrainDump = true })
                        .padding(.top, 8)
                        .transition(.blurReplace)
                } else {
                    Text("Swipe right to finish, left to plan. Hold a task for more.")
                }
            }

            Section {
                ForEach(store.data.habits) { h in
                    HabitLine(habit: h)
                        .swipeActions {
                            Button(role: .destructive) { withAnimation(.calm) { store.deleteHabit(h.id) } } label: { Label("Delete", systemImage: "trash") }
                        }
                }
                InlineAdd(placeholder: store.data.habits.isEmpty ? "Add a small daily habit" : "Add a habit",
                          color: Palette.habits, text: $habitTitle, focus: $focus, field: .habit, onSubmit: addHabit)
            } header: {
                Text("Daily habits")
            } footer: {
                Text("+5 XP each. Small enough to do on a bad day.")
            }

            if !store.finishedTasks.isEmpty {
                Section {
                    Button {
                        withAnimation(.calm) { showFinished.toggle() }
                    } label: {
                        HStack {
                            Text("Finished").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text("\(store.finishedTasks.count)").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(showFinished ? 90 : 0))
                        }
                    }
                    .buttonStyle(PressableStyle(haptic: .tick, scale: 0.99))
                    if showFinished {
                        ForEach(store.finishedTasks.prefix(50)) { t in
                            FinishedRow(task: t)
                                .swipeActions {
                                    Button { withAnimation(.calm) { store.restoreTask(t.id) } } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                                        .tint(Palette.habits)
                                }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background { AppBackground() }
        .navigationTitle("Work")
        .scrollDismissesKeyboard(.interactively)
        .animation(.calm, value: store.openTasks.map(\.id))
        .animation(.calm, value: store.data.habits.map(\.id))
    }

    private func addTask() {
        let t = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { focus = nil; return }
        withAnimation(.calm) { store.addTask(t) }
        newTitle = ""
        focus = .task
        Haptics.shared.play(.medium)
        SoundFX.shared.play(.pop)
    }

    private func addHabit() {
        let t = habitTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { focus = nil; return }
        withAnimation(.calm) { store.addHabit(t) }
        habitTitle = ""
        focus = .habit
        Haptics.shared.play(.medium)
        SoundFX.shared.play(.pop)
    }

    private func finish(_ t: WorkTask) {
        guard !finishing.contains(t.id) else { return }
        withAnimation(.reward) { _ = finishing.insert(t.id) }
        Haptics.shared.play(.success)
        SoundFX.shared.play(.pop)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.calm) { store.finishTask(t.id) }
            finishing.remove(t.id)
        }
    }
}

/// The add row used for tasks and habits: a plus that turns into a return arrow while typing.
private struct InlineAdd: View {
    let placeholder: String
    let color: Color
    @Binding var text: String
    var focus: FocusState<WorkView.Field?>.Binding
    let field: WorkView.Field
    let onSubmit: () -> Void
    var onMic: (() -> Void)? = nil
    var onScan: (() -> Void)? = nil

    var body: some View {
        let ready = !text.trimmingCharacters(in: .whitespaces).isEmpty
        HStack(spacing: 12) {
            Button {
                if ready { onSubmit() } else { focus.wrappedValue = field }
            } label: {
                Image(systemName: ready ? "arrow.up.circle.fill" : "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(color)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableStyle(haptic: .light, scale: 0.85))
            .accessibilityLabel(ready ? "Add" : "New")
            TextField(placeholder, text: $text)
                .focused(focus, equals: field)
                .submitLabel(.done)
                .onSubmit(onSubmit)
            if let onScan, !ready {
                Button(action: onScan) {
                    Image(systemName: "doc.viewfinder")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Palette.ember)
                        .frame(width: 32, height: 32)
                        .background(Palette.ember.opacity(0.12), in: Circle())
                }
                .buttonStyle(PressableStyle(haptic: .medium, scale: 0.85))
                .accessibilityLabel("Scan a page or screenshot into tasks")
                .transition(.scale.combined(with: .opacity))
            }
            if let onMic, !ready {
                Button(action: onMic) {
                    Image(systemName: "mic.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Palette.brand, in: Circle())
                }
                .buttonStyle(PressableStyle(haptic: .medium, scale: 0.85))
                .accessibilityLabel("Brain dump by voice")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.calm, value: ready)
    }
}

private struct TaskRow: View {
    @Environment(AppStore.self) private var store
    @Environment(DrawerCenter.self) private var drawers
    let task: WorkTask
    let finishing: Bool
    let onFinish: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onFinish) {
                CheckCircle(on: finishing)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle(haptic: .none, scale: 0.85))
            .accessibilityLabel("Finish \(task.title)")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .strikethrough(finishing, color: Palette.good)
                    .foregroundStyle(finishing ? Color.secondary : Color.primary)
                    .animation(.calm, value: finishing)
                if !task.steps.isEmpty {
                    Button {
                        drawers.present { BreakdownDrawer(taskID: task.id) }
                    } label: {
                        HStack(spacing: 6) {
                            Label("\(task.steps.filter(\.done).count)/\(task.steps.count)", systemImage: "list.bullet.indent")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color(hex: 0x0D9488))
                            if let next = task.steps.first(where: { !$0.done }) {
                                Text(next.title).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } else if let step = task.firstStep {
                    Button {
                        drawers.present { StepDrawer(taskID: task.id) }
                    } label: {
                        Label(step, systemImage: "shoeprints.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.ember)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
                if let due = task.due {
                    Label("Due " + due.formatted(Calendar.current.isDateInToday(due) ? Date.FormatStyle().hour().minute() : Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()),
                          systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(due < Date() ? Palette.bad : Palette.tasks)
                }
                HStack(spacing: 10) {
                    if task.focusMinutes > 0 {
                        Label("\(task.focusMinutes)m", systemImage: "timer").foregroundStyle(Palette.focus)
                    }
                    planLabel
                }
                .font(.caption.weight(.medium))
            }
            Spacer(minLength: 6)
            Button {
                store.sessionRequest = SessionConfig(taskID: task.id, minutes: store.data.defaultMinutes)
            } label: {
                Image(systemName: "play.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(TimerTheme.find(store.data.theme).gradient, in: Circle())
            }
            .buttonStyle(PressableStyle(haptic: .medium, scale: 0.88))
            .accessibilityLabel("Start focus on \(task.title)")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var planLabel: some View {
        if let at = task.plannedStart {
            switch task.planResult ?? "" {
            case "onTime": Label("On time", systemImage: "checkmark").foregroundStyle(Palette.good)
            case "late": Label("Started late", systemImage: "clock").foregroundStyle(Palette.tasks)
            case "missed": Label("Missed start", systemImage: "clock.badge.xmark").foregroundStyle(.secondary)
            default:
                Label(Calendar.current.isDateInToday(at) ? at.formatted(date: .omitted, time: .shortened)
                      : at.formatted(Date.FormatStyle().weekday(.abbreviated).hour().minute()),
                      systemImage: "alarm")
                    .foregroundStyle(Palette.habits)
            }
        }
    }
}

private struct FinishedRow: View {
    let task: WorkTask

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill((task.rarity ?? .common).color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).strikethrough().foregroundStyle(.secondary)
                Text("\((task.rarity ?? .common).name) · \(task.focusMinutes) min focused")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}
