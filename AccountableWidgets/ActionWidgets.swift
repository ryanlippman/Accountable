import WidgetKit
import SwiftUI
import AppIntents

// Widgets you can act on without opening the app.

struct ActionWidgets: WidgetBundle {
    var body: some Widget {
        HabitsWidget()
        TasksWidget()
        QuickStartWidget()
        BrainDumpWidget()
        FocusTimerWidget()
    }
}

// MARK: - Habits (tap to check off)

struct HabitsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HabitsWidget", provider: SnapProvider()) { e in
            HabitsWidgetView(e: e).widgetURL(deepToday)
        }
        .configurationDisplayName("Habits")
        .description("Tap a habit to check it off.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct HabitsWidgetView: View {
    let e: SnapEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let items = e.snap.habitItems ?? []
        let limit = family == .systemLarge ? 8 : (family == .systemMedium ? 4 : 3)
        let done = items.filter(\.done).count
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            HStack {
                Eyebrow(text: "Habits", color: Brand.habits)
                Spacer()
                if !items.isEmpty {
                    Text("\(done)/\(items.count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: Double(done)))
                }
            }
            if items.isEmpty {
                Spacer(minLength: 0)
                Text("Add a habit in the app and check it off here.")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else if family == .systemMedium {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(items.prefix(limit), id: \.id) { h in HabitButton(h: h, compact: false) }
                }
                Spacer(minLength: 0)
            } else {
                ForEach(items.prefix(limit), id: \.id) { h in HabitButton(h: h, compact: family == .systemSmall) }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .redacted(reason: e.real ? [] : .placeholder)
    }
}

private struct HabitButton: View {
    let h: WidgetSnapshot.HabitItem
    let compact: Bool
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        Button(intent: SetHabitIntent(habitID: h.id, done: !h.done)) {
            HStack(spacing: 8) {
                Image(systemName: h.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: compact ? 17 : 19, weight: .semibold))
                    .foregroundStyle(h.done ? Brand.habits : Color.secondary.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace))
                    .widgetAccentable()
                Text(h.title)
                    .font(.system(size: compact ? 13 : 14, weight: .semibold))
                    .foregroundStyle(h.done ? Color.secondary : Color.primary)
                    .strikethrough(h.done && mode == .fullColor, color: .secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if h.streak > 1 && !compact {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                        Text("\(h.streak)")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Brand.ember)
                }
            }
            .padding(.horizontal, compact ? 0 : 10)
            .padding(.vertical, compact ? 2 : 8)
            .background {
                if !compact {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(h.done ? Brand.habits.opacity(0.12) : Color.primary.opacity(0.05))
                }
            }
        }
        .buttonStyle(.plain)
        .invalidatableContent()
    }
}

// MARK: - Tasks (tap to finish, play to focus)

struct TasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TasksWidget", provider: SnapProvider()) { e in
            TasksWidgetView(e: e).widgetURL(deepToday)
        }
        .configurationDisplayName("Tasks")
        .description("Finish tasks or start focusing on one, right from your Home Screen.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct TasksWidgetView: View {
    let e: SnapEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let items = e.snap.taskItems ?? []
        let limit = family == .systemLarge ? 6 : 3
        VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 7) {
            HStack {
                Eyebrow(text: "To do", color: Brand.ember)
                Spacer()
                Text("\(e.snap.openTasks) open")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if items.isEmpty {
                Spacer(minLength: 0)
                HStack {
                    Text("All clear. Add something, or just focus.").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button(intent: BrainDumpIntent()) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Brand.gradient, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            } else {
                ForEach(items.prefix(limit), id: \.id) { t in TaskLine(t: t, theme: TimerTheme.find(e.snap.theme), large: family == .systemLarge) }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .redacted(reason: e.real ? [] : .placeholder)
    }
}

private struct TaskLine: View {
    let t: WidgetSnapshot.TaskItem
    let theme: TimerTheme
    let large: Bool
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        HStack(spacing: 10) {
            Button(intent: FinishTaskIntent(taskID: t.id)) {
                Image(systemName: "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .invalidatableContent()
            VStack(alignment: .leading, spacing: 1) {
                Text(t.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                if large, let step = t.step {
                    Text(step).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let at = t.start {
                Text(at, style: .time).font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.habits)
            }
            Button(intent: StartFocusIntent(minutes: 0, taskID: t.id)) {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(mode == .fullColor ? AnyShapeStyle(theme.gradient) : AnyShapeStyle(Color.primary.opacity(0.25)), in: Circle())
                    .widgetAccentable()
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Quick start (5-minute focus + brain dump)

struct QuickStartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickStartWidget", provider: SnapProvider()) { e in
            QuickStartView(e: e)
        }
        .configurationDisplayName("Quick start")
        .description("Start a 5-minute focus or a voice brain dump in one tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct QuickStartView: View {
    let e: SnapEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let s = e.snap
        let theme = TimerTheme.find(s.theme)
        Group {
            if family == .systemSmall {
                VStack(spacing: 8) {
                    bigButton(intent: StartFocusIntent(minutes: 5, taskID: s.nextTaskID), icon: "timer", title: "5 min",
                              fill: AnyShapeStyle(theme.gradient))
                    bigButton(intent: BrainDumpIntent(), icon: "mic.fill", title: "Dump",
                              fill: AnyShapeStyle(Color.primary.opacity(0.08)), light: true)
                }
            } else {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: "Next step", color: Brand.ember)
                        Text(s.nextTask ?? "Just focus")
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .lineLimit(2)
                        if let step = s.nextStep {
                            Text(step).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 4) {
                            FlameMark(lit: s.doneToday, size: 11)
                            Text(s.doneToday ? "\(s.streak)-day streak" : "Still time for today")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 8) {
                        bigButton(intent: StartFocusIntent(minutes: 5, taskID: s.nextTaskID), icon: "timer", title: "5 min",
                                  fill: AnyShapeStyle(theme.gradient))
                        bigButton(intent: BrainDumpIntent(), icon: "mic.fill", title: "Dump",
                                  fill: AnyShapeStyle(Color.primary.opacity(0.08)), light: true)
                    }
                    .frame(width: 120)
                }
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .redacted(reason: e.real ? [] : .placeholder)
    }

    private func bigButton(intent: some AppIntent, icon: String, title: String, fill: AnyShapeStyle, light: Bool = false) -> some View {
        Button(intent: intent) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 15, weight: .bold))
                Text(title).font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundStyle(light || mode != .fullColor ? Color.primary : Color.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(mode == .fullColor ? fill : AnyShapeStyle(Color.primary.opacity(0.12)),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .widgetAccentable(!light)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Brain dump

struct BrainDumpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BrainDumpWidget", provider: SnapProvider()) { e in
            BrainDumpWidgetView(e: e).widgetURL(AppRoute.dump)
        }
        .configurationDisplayName("Brain dump")
        .description("Tap and say everything on your mind. It becomes tasks.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

private struct BrainDumpWidgetView: View {
    let e: SnapEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill").font(.system(size: 22, weight: .semibold)).widgetAccentable()
            }
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "mic.circle.fill").font(.system(size: 28)).widgetAccentable()
                VStack(alignment: .leading, spacing: 0) {
                    Text("Brain dump").font(.headline)
                    Text("Say it all. Get tasks.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .containerBackground(for: .widget) { Color.clear }
        default:
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Circle()
                        .fill(mode == .fullColor ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.2)))
                        .widgetAccentable()
                    Image(systemName: "mic.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 54, height: 54)
                .shadow(color: Brand.rose.opacity(mode == .fullColor ? 0.45 : 0), radius: 12, y: 5)
                Spacer(minLength: 0)
                Text("Brain dump").font(.system(.headline, design: .rounded).weight(.bold)).foregroundStyle(.white)
                Text("Say everything. Get tiny next steps.")
                    .font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(for: .widget) {
                ZStack {
                    Color(hex: 0x111116)
                    RadialGradient(colors: [Brand.rose.opacity(0.35), .clear], center: .topLeading, startRadius: 0, endRadius: 180)
                }
            }
        }
    }
}

// MARK: - Control Center, Lock Screen controls and the Action button

#if !targetEnvironment(macCatalyst)

struct FocusControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.ryanlippman.accountable.focus") {
            ControlWidgetButton(action: StartFocusIntent(minutes: 5)) {
                Label("Focus 5 min", systemImage: "timer")
            }
        }
        .displayName("Start focus")
        .description("Start a 5-minute focus session.")
    }
}

struct BrainDumpControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.ryanlippman.accountable.dump") {
            ControlWidgetButton(action: BrainDumpIntent()) {
                Label("Brain dump", systemImage: "mic.fill")
            }
        }
        .displayName("Brain dump")
        .description("Say what's on your mind and turn it into tasks.")
    }
}

#endif

// MARK: - Focus timer (made for StandBy)

struct FocusTimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FocusTimerWidget", provider: SnapProvider()) { e in
            FocusTimerView(e: e).widgetURL(deepToday)
        }
        .configurationDisplayName("Focus timer")
        .description("Your running session as a big clock. Great in StandBy while your phone charges.")
        .supportedFamilies([.systemSmall])
    }
}

private struct FocusTimerView: View {
    let e: SnapEntry
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    var body: some View {
        let s = e.snap
        let theme = TimerTheme.find(s.theme)
        Group {
            if let start = s.focusStart, let end = s.focusEnd, end > e.date {
                VStack(spacing: 6) {
                    let up = s.focusCountsUp ?? false
                    ZStack {
                        if up {
                            // A stopwatch has no end to fill toward: a steady lit ring instead.
                            Circle()
                                .stroke(theme.c1, style: StrokeStyle(lineWidth: 4, dash: [2, 5]))
                                .widgetAccentable()
                        } else {
                            ProgressView(timerInterval: start...max(end, start.addingTimeInterval(1)), countsDown: false,
                                         label: { EmptyView() }, currentValueLabel: { EmptyView() })
                                .progressViewStyle(.circular)
                                .tint(theme.c1)
                                .widgetAccentable()
                        }
                        Text(timerInterval: start...max(end, start.addingTimeInterval(1)), countsDown: !up, showsHours: up)
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 14)
                    }
                    Text(s.focusTitle ?? "Focus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        FlameMark(lit: s.doneToday, size: 18)
                        Text("\(s.streak)").font(.system(size: 18, weight: .bold, design: .rounded))
                        Spacer()
                    }
                    Spacer(minLength: 0)
                    Text("Ready to focus").font(.system(.headline, design: .rounded).weight(.bold))
                    Button(intent: StartFocusIntent(minutes: 0, taskID: s.nextTaskID)) {
                        Label("Start", systemImage: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(mode == .fullColor ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(mode == .fullColor ? AnyShapeStyle(theme.gradient) : AnyShapeStyle(Color.primary.opacity(0.15)), in: Capsule())
                            .widgetAccentable()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .containerBackground(for: .widget) { showsBackground ? Color(hex: 0x0D0D12) : Color.clear }
        .environment(\.colorScheme, .dark)
        .redacted(reason: e.real ? [] : .placeholder)
    }
}
