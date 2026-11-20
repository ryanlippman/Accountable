import WidgetKit
import SwiftUI

// MARK: - Timeline

struct SnapEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot
    let real: Bool
}

struct SnapProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapEntry {
        SnapEntry(date: Date(), snap: .placeholder, real: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapEntry) -> Void) {
        if let s = WidgetSnapshot.load() {
            completion(SnapEntry(date: Date(), snap: s.normalized(), real: true))
        } else {
            completion(SnapEntry(date: Date(), snap: .placeholder, real: context.isPreview))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapEntry>) -> Void) {
        let now = Date()
        guard let s = WidgetSnapshot.load() else {
            completion(Timeline(entries: [SnapEntry(date: now, snap: .placeholder, real: false)], policy: .after(now.addingTimeInterval(1800))))
            return
        }
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400 + 5)
        var entries = [SnapEntry(date: now, snap: s.normalized(at: now), real: true),
                       SnapEntry(date: midnight, snap: s.normalized(at: midnight), real: true)]
        // When a round ends, the timer widget goes back to "Ready to focus".
        if let end = s.focusEnd, end > now, end < midnight {
            var after = s.normalized(at: end)
            after.focusStart = nil
            after.focusEnd = nil
            entries.insert(SnapEntry(date: end.addingTimeInterval(1), snap: after, real: true), at: 1)
        }
        completion(Timeline(entries: entries, policy: .after(min(midnight, now.addingTimeInterval(1800)))))
    }
}

// MARK: - Bundle

@main
struct AccountableWidgets: WidgetBundle {
    var body: some Widget {
        GlanceWidgets().body
        ActionWidgets().body
        #if !targetEnvironment(macCatalyst)
        FocusLiveActivity()
        FocusControl()
        BrainDumpControl()
        #endif
    }
}

struct GlanceWidgets: WidgetBundle {
    var body: some Widget {
        StreakWidget()
        ScoreWidget()
        NextStepWidget()
        TodayWidget()
    }
}

// MARK: - Shared pieces

let deepToday = URL(string: "\(SharedConfig.scheme)://today")!
let deepQuests = URL(string: "\(SharedConfig.scheme)://progress")!

func focusURL(_ id: String?) -> URL {
    URL(string: "\(SharedConfig.scheme)://focus" + (id.map { "?task=\($0)" } ?? ""))!
}

struct Eyebrow: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(color)
    }
}

/// Segmented focus-score ring. In tinted or clear modes it collapses to a single accentable ring.
private struct ScoreRingView: View {
    let s: WidgetSnapshot
    var width: CGFloat = 9
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: width)
            if mode == .fullColor {
                let parts: [(Double, Color)] = [(Double(s.scoreTasks) / 100, Brand.tasks),
                                                (Double(s.scoreFocus) / 100, Brand.focus),
                                                (Double(s.scoreHabits) / 100, Brand.habits)]
                ForEach(0..<3, id: \.self) { i in
                    let start = parts.prefix(i).reduce(0) { $0 + $1.0 }
                    if parts[i].0 > 0.001 {
                        Circle()
                            .trim(from: start, to: start + max(0.002, parts[i].0 - 0.008))
                            .stroke(parts[i].1, style: StrokeStyle(lineWidth: width, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                    }
                }
            } else {
                Circle()
                    .trim(from: 0, to: Double(s.score) / 100)
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }
        }
    }
}

struct FlameMark: View {
    let lit: Bool
    var size: CGFloat
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        Image(systemName: "flame.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(lit && mode == .fullColor ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(lit ? 1 : 0.3)))
            .widgetAccentable()
    }
}

private struct WeekDots: View {
    let s: WidgetSnapshot
    var size: CGFloat = 9

    var body: some View {
        HStack(spacing: size * 0.55) {
            ForEach(0..<7, id: \.self) { i in
                Circle()
                    .fill(s.weekDone[i] ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(i > s.todayIndex ? 0.06 : 0.14)))
                    .frame(width: size, height: size)
                    .overlay {
                        if i == s.todayIndex && !s.weekDone[i] {
                            Circle().stroke(Brand.ember, lineWidth: 1.5)
                        }
                    }
                    .widgetAccentable(s.weekDone[i])
            }
        }
    }
}

private struct WarmBackground: View {
    let lit: Bool
    var body: some View {
        ZStack {
            Color(hex: 0x14100E)
            RadialGradient(colors: [Color(hex: 0xFF5A2C).opacity(lit ? 0.55 : 0.18), .clear],
                           center: UnitPoint(x: 0.15, y: 0.0), startRadius: 0, endRadius: 190)
        }
    }
}

// MARK: - Streak

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StreakWidget", provider: SnapProvider()) { e in
            StreakView(e: e).widgetURL(deepToday)
        }
        .configurationDisplayName("Streak")
        .description("Your streak and this week at a glance.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

private struct StreakView: View {
    let e: SnapEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let s = e.snap
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: -2) {
                        FlameMark(lit: s.doneToday, size: 16)
                        Text("\(s.streak)").font(.system(size: 20, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
                    }
                }
                .containerBackground(for: .widget) { Color.clear }
            case .accessoryInline:
                Label(s.doneToday ? "\(s.streak)-day streak" : "\(s.streak) days · start today", systemImage: "flame.fill")
                    .containerBackground(for: .widget) { Color.clear }
            default:
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        FlameMark(lit: s.doneToday, size: 22)
                        Spacer()
                        Eyebrow(text: s.doneToday ? "Done today" : "Not yet", color: .white.opacity(0.6))
                    }
                    Spacer(minLength: 0)
                    Text("\(s.streak)")
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText(value: Double(s.streak)))
                    Text(s.streak == 1 ? "day streak" : "day streak")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer(minLength: 8)
                    WeekDots(s: s, size: 11)
                }
                .containerBackground(for: .widget) { WarmBackground(lit: s.doneToday) }
            }
        }
        .redacted(reason: e.real ? [] : .placeholder)
    }
}

// MARK: - Focus score

struct ScoreWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ScoreWidget", provider: SnapProvider()) { e in
            ScoreView(e: e).widgetURL(deepToday)
        }
        .configurationDisplayName("Focus score")
        .description("Today's score from tasks, focus time and habits.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

private struct ScoreView: View {
    let e: SnapEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let s = e.snap
        Group {
            if family == .accessoryCircular {
                Gauge(value: Double(s.score), in: 0...100) {
                    Image(systemName: "scope")
                } currentValueLabel: {
                    Text("\(s.score)").font(.system(.body, design: .rounded).weight(.bold))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
                .containerBackground(for: .widget) { Color.clear }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Focus score")
                    ZStack {
                        ScoreRingView(s: s, width: 11)
                        VStack(spacing: -2) {
                            Text("\(s.score)").font(.system(size: 30, weight: .heavy, design: .rounded))
                            Text("of 100").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    HStack(spacing: 6) {
                        Dot(color: Brand.tasks, value: s.scoreTasks)
                        Dot(color: Brand.focus, value: s.scoreFocus)
                        Dot(color: Brand.habits, value: s.scoreHabits)
                    }
                    .frame(maxWidth: .infinity)
                }
                .containerBackground(for: .widget) { Color(.systemBackground) }
            }
        }
        .redacted(reason: e.real ? [] : .placeholder)
    }
}

private struct Dot: View {
    let color: Color
    let value: Int
    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(value)").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Next step

struct NextStepWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextStepWidget", provider: SnapProvider()) { e in
            NextStepView(e: e).widgetURL(focusURL(e.snap.nextTaskID))
        }
        .configurationDisplayName("Next step")
        .description("The one thing to do next, with a button to start.")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

private struct NextStepView: View {
    let e: SnapEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let s = e.snap
        let theme = TimerTheme.find(s.theme)
        Group {
            if family == .accessoryRectangular {
                VStack(alignment: .leading, spacing: 1) {
                    Label("Next step", systemImage: "arrow.forward.circle.fill").font(.caption2.weight(.bold)).widgetAccentable()
                    Text(s.nextTask ?? "Nothing planned").font(.headline).lineLimit(1)
                    Text(s.nextStep ?? "Open Accountable to add one").font(.caption).lineLimit(1).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .containerBackground(for: .widget) { Color.clear }
            } else {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow(text: "Your next step")
                        Text(s.nextTask ?? "Nothing on your list")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .lineLimit(2)
                        if let step = s.nextStep, !step.isEmpty {
                            Text(step).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 10) {
                            if let at = s.nextStart {
                                Label(at.formatted(date: .omitted, time: .shortened), systemImage: "alarm")
                            }
                            Label("\(s.openTasks) open", systemImage: "checklist")
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Link(destination: focusURL(s.nextTaskID)) {
                        ZStack {
                            Circle()
                                .fill(mode == .fullColor ? AnyShapeStyle(theme.gradient) : AnyShapeStyle(Color.primary.opacity(0.2)))
                                .widgetAccentable()
                            Image(systemName: "play.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: 2)
                        }
                        .frame(width: 58, height: 58)
                        .shadow(color: theme.c2.opacity(mode == .fullColor ? 0.4 : 0), radius: 10, y: 4)
                    }
                }
                .containerBackground(for: .widget) { Color(.systemBackground) }
            }
        }
        .redacted(reason: e.real ? [] : .placeholder)
    }
}

// MARK: - Today

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: SnapProvider()) { e in
            TodayWidgetView(e: e).widgetURL(deepQuests)
        }
        .configurationDisplayName("Today")
        .description("Focus score, XP and today's quests.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct TodayWidgetView: View {
    let e: SnapEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let s = e.snap
        Group {
            if family == .systemLarge { large(s) } else { medium(s) }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .redacted(reason: e.real ? [] : .placeholder)
    }

    private func medium(_ s: WidgetSnapshot) -> some View {
        HStack(spacing: 16) {
            VStack(spacing: 6) {
                ZStack {
                    ScoreRingView(s: s, width: 10)
                    Text("\(s.score)").font(.system(size: 24, weight: .heavy, design: .rounded))
                }
                .frame(width: 84, height: 84)
                xpLine(s)
            }
            .frame(width: 96)
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Daily quests")
                ForEach(s.quests.prefix(3), id: \.self) { q in questRow(q) }
            }
        }
    }

    private func large(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Level \(s.level) · \(s.levelTitle)").font(.headline)
                    ProgressView(value: s.levelProgress).tint(Brand.ember).frame(maxWidth: 160)
                }
                Spacer()
                HStack(spacing: 4) {
                    FlameMark(lit: s.doneToday, size: 18)
                    Text("\(s.streak)").font(.system(.title3, design: .rounded).weight(.bold))
                }
            }
            HStack(spacing: 18) {
                ZStack {
                    ScoreRingView(s: s, width: 12)
                    VStack(spacing: -2) {
                        Text("\(s.score)").font(.system(size: 30, weight: .heavy, design: .rounded))
                        Text("focus").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 104, height: 104)
                VStack(alignment: .leading, spacing: 8) {
                    stat("checkmark.seal.fill", Brand.tasks, "\(s.scoreTasks)/45 tasks")
                    stat("timer", Brand.focus, "\(s.focusMinutesToday) min focused")
                    stat("repeat", Brand.habits, s.habitsTotal > 0 ? "\(s.habitsDone) of \(s.habitsTotal) habits" : "\(s.sessionsToday) sessions")
                    xpLine(s)
                }
            }
            Divider()
            Eyebrow(text: "Daily quests")
            ForEach(s.quests.prefix(3), id: \.self) { q in questRow(q) }
            Divider()
            Link(destination: focusURL(s.nextTaskID)) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Eyebrow(text: "Next step")
                        Text(s.nextTask ?? "Just focus").font(.subheadline.weight(.semibold)).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "play.circle.fill").font(.title).foregroundStyle(TimerTheme.find(s.theme).gradient)
                }
            }
        }
    }

    private func stat(_ icon: String, _ color: Color, _ text: String) -> some View {
        Label {
            Text(text).font(.caption.weight(.semibold))
        } icon: {
            Image(systemName: icon).foregroundStyle(color).font(.caption)
        }
    }

    private func xpLine(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ProgressView(value: min(1, Double(s.xpToday) / Double(max(1, s.dailyGoal))))
                .tint(Brand.xp)
            Text("\(s.xpToday)/\(s.dailyGoal) XP").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
        }
    }

    private func questRow(_ q: WidgetSnapshot.QuestItem) -> some View {
        let done = q.progress >= q.target
        return HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : q.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(done ? Brand.good : Brand.ember)
                .frame(width: 16)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 3) {
                Text(q.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                ProgressView(value: min(1, Double(q.progress) / Double(max(1, q.target))))
                    .tint(done ? Brand.good : Brand.ember)
            }
        }
    }
}
