#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
import WidgetKit
import SwiftUI

// The running focus session on the Lock Screen, in the Dynamic Island and in StandBy.
// Clocks and rings run by themselves (Text and ProgressView with a timer interval), so the app only
// pushes an update when something changes: the phase, a combo, the phone flipping, or time added back.
//
// Timer: counts down, the ring fills toward the end, and the Lock Screen says when it ends.
// Stopwatch: counts up, the ring fills toward the next five-minute combo, and it says when you started.

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { ctx in
            LockScreenFocus(ctx: ctx)
                .activityBackgroundTint(Color(hex: 0x0D0D12).opacity(0.94))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(deepToday)
        } dynamicIsland: { ctx in
            let s = ctx.state
            let a = ctx.attributes
            let c1 = Color(hex: a.hex1), c2 = Color(hex: a.hex2)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RingBadge(state: s, c1: c1, c2: c2, size: 52, line: 5)
                        .padding(.leading, 6)
                        .padding(.top, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        TimerText(state: s, size: 32)
                            .foregroundStyle(.white)
                        SubLine(state: s)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: 130, alignment: .trailing)
                    .padding(.trailing, 6)
                    .padding(.top, 8)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 3) {
                        PhaseLabel(state: s, c1: c1, c2: c2)
                        Text(a.taskTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if s.phase == "done" {
                        DoneRow(state: s, c1: c1)
                            .padding(.horizontal, 6)
                            .padding(.top, 4)
                    } else if s.phase == "starter" {
                        StarterRow(state: s, c1: c1, c2: c2)
                            .padding(.horizontal, 6)
                            .padding(.top, 4)
                    } else {
                        VStack(spacing: 10) {
                            BarRow(state: s, c1: c1)
                            HStack(spacing: 8) {
                                ComboDots(combo: s.combo, c1: c1, c2: c2)
                                if s.faceDown {
                                    Chip(icon: "iphone.slash", text: "+50%", tint: c1)
                                }
                                Spacer(minLength: 0)
                                XPText(xp: s.xp, size: 13)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.top, 4)
                    }
                }
            } compactLeading: {
                RingBadge(state: s, c1: c1, c2: c2, size: 22, line: 2.5, icon: true, compact: true)
                    .padding(.leading, 2)
            } compactTrailing: {
                TimerText(state: s, size: 15, compact: true)
                    .foregroundStyle(c1)
                    .frame(maxWidth: s.stopwatch ? 58 : 46)
            } minimal: {
                RingBadge(state: s, c1: c1, c2: c2, size: 22, line: 2.5, icon: true, compact: true)
            }
            .keylineTint(c1)
            .widgetURL(deepToday)
        }
    }
}

// MARK: - Time math

private func timerRange(_ s: FocusActivityAttributes.ContentState) -> ClosedRange<Date> {
    s.start...max(s.end, s.start.addingTimeInterval(1))
}

/// What the ring tracks: the whole round on a timer, the current combo window on a stopwatch.
private func ringRange(_ s: FocusActivityAttributes.ContentState) -> ClosedRange<Date> {
    if s.stopwatch && s.phase == "focus" { return s.lap...s.lap.addingTimeInterval(300) }
    return timerRange(s)
}

// MARK: - Lock Screen

private struct LockScreenFocus: View {
    let ctx: ActivityViewContext<FocusActivityAttributes>
    /// True in StandBy, when the phone is charging on its side and the activity fills the screen.
    @Environment(\.isActivityFullscreen) private var fullscreen

    var body: some View {
        if fullscreen { StandByFocus(ctx: ctx) } else { regular }
    }

    private var regular: some View {
        let s = ctx.state
        let a = ctx.attributes
        let c1 = Color(hex: a.hex1), c2 = Color(hex: a.hex2)
        return VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                RingBadge(state: s, c1: c1, c2: c2, size: 54, line: 5.5)
                VStack(alignment: .leading, spacing: 3) {
                    PhaseLabel(state: s, c1: c1, c2: c2)
                    Text(a.taskTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    SubLine(state: s)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    TimerText(state: s, size: 38)
                        .foregroundStyle(.white)
                    if s.phase != "done" {
                        XPText(xp: s.xp, size: 12)
                    }
                }
                .frame(maxWidth: 140, alignment: .trailing)
            }
            if s.phase == "done" {
                DoneRow(state: s, c1: c1)
            } else if s.phase == "starter" {
                StarterRow(state: s, c1: c1, c2: c2)
            } else {
                VStack(spacing: 10) {
                    BarRow(state: s, c1: c1)
                    HStack(spacing: 8) {
                        ComboDots(combo: s.combo, c1: c1, c2: c2)
                        Spacer(minLength: 0)
                        if s.faceDown {
                            Chip(icon: "iphone.slash", text: "Phone down · +50%", tint: c1)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

/// StandBy: a big, quiet desk clock for the round.
private struct StandByFocus: View {
    let ctx: ActivityViewContext<FocusActivityAttributes>

    var body: some View {
        let s = ctx.state
        let a = ctx.attributes
        let c1 = Color(hex: a.hex1), c2 = Color(hex: a.hex2)
        HStack(spacing: 24) {
            RingBadge(state: s, c1: c1, c2: c2, size: 84, line: 8)
            VStack(alignment: .leading, spacing: 4) {
                PhaseLabel(state: s, c1: c1, c2: c2)
                Text(a.taskTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                TimerText(state: s, size: 68)
                    .foregroundStyle(LinearGradient(colors: [c1, c2], startPoint: .top, endPoint: .bottom))
                    .multilineTextAlignment(.leading)
                SubLine(state: s)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
    }
}

// MARK: - Pieces

private struct PhaseLabel: View {
    let state: FocusActivityAttributes.ContentState
    let c1: Color
    let c2: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .foregroundStyle(c1)
        }
    }

    private var text: String {
        switch state.phase {
        case "starter": return "STARTER"
        case "done": return "SESSION COMPLETE"
        default:
            if state.faceDown { return "PHONE DOWN" }
            return state.stopwatch ? "STOPWATCH" : "FOCUS"
        }
    }
}

/// One quiet line of context: when it ends, when it started, or what's left of the starter.
private struct SubLine: View {
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case "done":
            Text("Nice work")
        case "starter":
            Text("Focus at ") + Text(state.end, style: .time)
        default:
            if state.stopwatch {
                Text("Since ") + Text(state.start, style: .time)
            } else {
                Text("Ends ") + Text(state.end, style: .time)
            }
        }
    }
}

/// A ring that fills by itself: toward the end of a timer, or toward the next combo on a stopwatch.
private struct RingBadge: View {
    let state: FocusActivityAttributes.ContentState
    let c1: Color
    let c2: Color
    let size: CGFloat
    let line: CGFloat
    var icon = true
    var compact = false

    var body: some View {
        ZStack {
            if state.phase == "done" {
                Circle().fill(LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "checkmark").font(.system(size: size * 0.42, weight: .heavy)).foregroundStyle(.white)
            } else {
                ProgressView(timerInterval: ringRange(state), countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                    .progressViewStyle(.circular)
                    .tint(c1)
                    .frame(width: size, height: size)
                if icon {
                    Image(systemName: symbol)
                        .font(.system(size: size * (compact ? 0.42 : 0.36), weight: .bold))
                        .foregroundStyle(c1)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private var symbol: String {
        if state.phase == "starter" { return "figure.walk" }
        if state.faceDown { return "iphone.slash" }
        return state.stopwatch ? "stopwatch.fill" : "flame.fill"
    }
}

private struct TimerText: View {
    let state: FocusActivityAttributes.ContentState
    let size: CGFloat
    var compact = false

    var body: some View {
        Group {
            if state.phase == "done" {
                Text(compact ? "Done" : "+\(state.xp) XP")
            } else if state.stopwatch && state.phase == "focus" {
                Text(timerInterval: timerRange(state), countsDown: false, showsHours: true)
            } else {
                Text(timerInterval: timerRange(state), countsDown: true, showsHours: false)
            }
        }
        .font(.system(size: size, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .contentTransition(.numericText())
    }
}

/// Progress across the bottom, labeled with what it's filling toward.
private struct BarRow: View {
    let state: FocusActivityAttributes.ContentState
    let c1: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ProgressView(timerInterval: ringRange(state), countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                .progressViewStyle(.linear)
                .tint(c1)
            if state.stopwatch && state.phase == "focus" {
                Text("Next combo")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}

/// Earned combos as lit dots, so progress is readable at a glance.
private struct ComboDots: View {
    let combo: Int
    let c1: Color
    let c2: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(combo > 0 ? c1 : .white.opacity(0.35))
            ForEach(0..<6, id: \.self) { i in
                Circle()
                    .fill(i < min(combo, 6)
                          ? AnyShapeStyle(LinearGradient(colors: [c1, c2], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.white.opacity(0.12)))
                    .frame(width: 6, height: 6)
            }
            if combo > 0 {
                Text("×\(combo)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(c1)
                    .contentTransition(.numericText(value: Double(combo)))
            }
        }
    }
}

private struct XPText: View {
    let xp: Int
    let size: CGFloat

    var body: some View {
        Text("+\(xp) XP")
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Brand.xp)
            .contentTransition(.numericText(value: Double(xp)))
    }
}

/// The 2-minute starter: one instruction and two steps, so it's obvious what happens next.
private struct StarterRow: View {
    let state: FocusActivityAttributes.ContentState
    let c1: Color
    let c2: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Just do the smallest first step.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            HStack(spacing: 6) {
                // Step one fills by itself over the two minutes; step two waits its turn.
                ProgressView(timerInterval: timerRange(state), countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                    .progressViewStyle(.linear)
                    .tint(c1)
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 70, height: 4)
            }
            HStack {
                Text("Starter")
                Spacer()
                Text(state.stopwatch ? "Stopwatch" : "Focus")
                    .foregroundStyle(.white.opacity(0.35))
            }
            .font(.system(size: 10, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(c1)
        }
    }
}

private struct DoneRow: View {
    let state: FocusActivityAttributes.ContentState
    let c1: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(c1)
            Text("Session saved")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            if state.combo > 0 {
                Text("Best ×\(state.combo)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

private struct Chip: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.08), in: Capsule())
    }
}
#endif
