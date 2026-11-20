import SwiftUI
import UIKit

// Visual system: native iOS surfaces (grouped backgrounds, inset cards, system type) with the web app's
// ring language, and a dark focus screen lit by the timer color.
//
// Motion rules, taken from Apple's fluid-interface guidance:
// • Feedback starts on touch-down, never on release.
// • Springs everywhere, critically damped by default. Overshoot only where a gesture carried momentum
//   or a reward is being given.
// • Anything you can drag tracks 1:1, rubber-bands at its limits, and on release projects its momentum
//   before deciding where to land, handing the finger's velocity to the spring.
// • Things leave the way they came in.
// • Reduce Motion swaps movement for cross-fades.

enum Palette {
    static let ember = Brand.ember
    static let rose = Brand.rose
    static let tasks = Brand.tasks
    static let focus = Brand.focus
    static let habits = Brand.habits
    static let xp = Brand.xp
    static let good = Brand.good
    static let spark = Color(hex: 0x8B5CF6)
    static let shield = Color(hex: 0x2FA8FF)
    static let bad = Color(hex: 0xE0484D)

    static let bg = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let raised = Color(.tertiarySystemGroupedBackground)
    static let track = Color(.tertiarySystemFill)

    static let night = Color(hex: 0x0A0A0F)
    static let nightRaised = Color(hex: 0x17171F)
    static let nightInk = Color(hex: 0xF7F7FA)
    static let nightMuted = Color(hex: 0x9A9AA8)
    static let nightChip = Color.white.opacity(0.07)
    static let nightLine = Color.white.opacity(0.10)

    static let brand = Brand.gradient
}

extension Animation {
    /// Touch-down: fast, no overshoot, so the press lands within a frame or two.
    static let press = Animation.interactiveSpring(response: 0.16, dampingFraction: 1)
    /// Release: a calm spring back that can be interrupted by the next press.
    static let release = Animation.spring(response: 0.32, dampingFraction: 0.82)
    /// Critically damped: the house default for UI that moves.
    static let calm = Animation.spring(response: 0.35, dampingFraction: 1)
    /// Sheets and drawers.
    static let drawer = Animation.spring(response: 0.34, dampingFraction: 0.86)
    /// A little overshoot, only for moments of reward.
    static let reward = Animation.spring(response: 0.42, dampingFraction: 0.72)
}

enum Motion {
    /// Apple's momentum projection: where a flick would come to rest (deceleration 0.998, like scrolling).
    static func project(_ velocity: CGFloat, deceleration: CGFloat = 0.998) -> CGFloat {
        (velocity / 1000) * deceleration / (1 - deceleration)
    }

    /// Progressive resistance past a boundary: things slow before they stop.
    static func rubberband(_ overshoot: CGFloat, dimension: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
        (overshoot * dimension * constant) / (dimension + constant * abs(overshoot))
    }

    /// Spring that starts at the finger's speed. `distance` is how far is left to travel.
    static func handoff(velocity: CGFloat, distance: CGFloat, bounce: Double = 0) -> Animation {
        let rel = abs(distance) > 1 ? Double(velocity / distance) : 0
        return .interpolatingSpring(duration: 0.38, bounce: bounce, initialVelocity: max(-30, min(30, rel)))
    }
}

// MARK: - Surfaces

/// Cards: continuous corners, a hairline edge and a soft two-layer shadow in light mode
/// (a contact shadow plus a wide ambient one), so they read as surfaces rather than gray boxes.
struct CardStyle: ViewModifier {
    var padding: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let radius: CGFloat = padding >= 18 ? 28 : 22
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape
                    .fill(Palette.card)
                    .overlay(shape.strokeBorder(Color.primary.opacity(scheme == .dark ? 0.08 : 0.045), lineWidth: 1))
                    .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.035), radius: 1, y: 1)
                    .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.06), radius: 18, y: 8)
            }
    }
}

extension View {
    func card(_ padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }

    /// Cards ease in and out as they cross the scroll edges, instead of being clipped by them.
    func scrollEdgeFade() -> some View {
        scrollTransition(.interactive, axis: .vertical) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.6)
                .scaleEffect(phase.isIdentity ? 1 : 0.97, anchor: phase.value < 0 ? .bottom : .top)
        }
    }
}

/// For tappable cards and rows: shrinks a touch on press-down with a light haptic, springs back calmly.
struct PressableStyle: ButtonStyle {
    var haptic: Haptics.Kind = .light
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration, haptic: haptic, scale: scale)
    }
}

private struct PressableBody: View {
    let configuration: ButtonStyleConfiguration
    let haptic: Haptics.Kind
    let scale: CGFloat

    var body: some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(configuration.isPressed ? .press : .release, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, down in
                if down { Haptics.shared.play(haptic) }
            }
    }
}

/// The big capsule used for primary actions. `dark` is the white-on-night version for the focus screens.
struct GlowButtonStyle: ButtonStyle {
    var theme: TimerTheme = TimerTheme.find("ember")
    var dark = false
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        GlowBody(configuration: configuration, theme: theme, dark: dark, tint: tint)
    }
}

private struct GlowBody: View {
    let configuration: ButtonStyleConfiguration
    let theme: TimerTheme
    let dark: Bool
    let tint: Color?
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(dark ? Color.black : Color.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                Capsule()
                    .fill(dark ? AnyShapeStyle(Color.white) : (tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(theme.gradient)))
                    .overlay {
                        Capsule()
                            .strokeBorder(LinearGradient(colors: [Color.white.opacity(dark ? 0 : 0.35), .clear],
                                                         startPoint: .top, endPoint: .center), lineWidth: 1)
                    }
                    .shadow(color: (tint ?? theme.c2).opacity(enabled && !dark ? (configuration.isPressed ? 0.2 : 0.35) : 0),
                            radius: configuration.isPressed ? 8 : 14, y: configuration.isPressed ? 3 : 7)
            }
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(configuration.isPressed ? .press : .release, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, down in
                if down && enabled {
                    Haptics.shared.play(.medium)
                    SoundFX.shared.play(.tap)
                }
            }
    }
}

/// Quiet secondary action: tinted text in a soft capsule.
struct SoftButtonStyle: ButtonStyle {
    var color: Color = Palette.ember
    var dark = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(dark ? Palette.nightInk : color)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .background((dark ? Color.white.opacity(0.08) : color.opacity(0.12)), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(configuration.isPressed ? .press : .release, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, down in if down { Haptics.shared.play(.light) } }
    }
}

// MARK: - Rings (the web app's visual language)

struct Ring: View {
    var progress: Double
    var lineWidth: CGFloat = 6
    var color: Color = .primary
    var dashedWhenEmpty = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.track, style: StrokeStyle(lineWidth: lineWidth, dash: dashedWhenEmpty && progress <= 0 ? [2.5, 3.5] : []))
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(progress >= 1 ? 0.45 : 0), radius: lineWidth * 0.8)
        }
        .animation(.spring(response: 0.8, dampingFraction: 1), value: progress)
    }
}

/// Focus score ring: three colored segments with small gaps, like the web hero ring.
struct ScoreRing: View {
    var score: DayScore
    var lineWidth: CGFloat = 11

    var body: some View {
        let parts: [(Double, Color)] = [(Double(score.tasks) / 100, Palette.tasks),
                                        (Double(score.focus) / 100, Palette.focus),
                                        (Double(score.habits) / 100, Palette.habits)]
        ZStack {
            Circle().stroke(Palette.track, lineWidth: lineWidth)
            ForEach(0..<3, id: \.self) { i in
                let start = parts.prefix(i).reduce(0) { $0 + $1.0 }
                let len = parts[i].0
                Circle()
                    .trim(from: start, to: start + (len > 0.001 ? max(0.002, len - 0.008) : 0))
                    .stroke(parts[i].1, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(.spring(response: 0.9, dampingFraction: 1), value: score.total)
    }
}

struct Bar: View {
    var value: Double
    var color: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule().fill(color)
                    .frame(width: max(value > 0 ? height : 0, geo.size.width * max(0, min(1, value))))
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.6, dampingFraction: 1), value: value)
    }
}

/// Number that counts up when it appears, ticking a light haptic as it climbs.
struct CountUpText: View {
    let target: Int
    var delay: Double = 0
    var font: Font = .system(size: 28, weight: .bold, design: .rounded)
    var color: Color = .primary
    var suffix: String = ""
    @State private var shown = 0

    var body: some View {
        Text("\(shown)\(suffix)")
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(shown)))
            .task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                let steps = min(max(target, 1), 16)
                for i in 1...steps {
                    try? await Task.sleep(nanoseconds: 36_000_000)
                    withAnimation(.snappy(duration: 0.12)) { shown = Int((Double(target) * Double(i) / Double(steps)).rounded()) }
                    if i % 2 == 0 { Haptics.shared.play(.tick) }
                }
                shown = target
            }
    }
}

/// Small status capsule for the toolbar (streak, sparks, shields).
struct StatChip: View {
    let icon: String
    let value: Int
    let color: Color
    var dim = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(dim ? Color.secondary : color)
                .symbolEffect(.bounce, value: value)
            Text("\(value)")
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
                .foregroundStyle(dim ? Color.secondary : Color.primary)
        }
        .font(.subheadline.weight(.semibold))
        .modifier(ChipContainer())
        .animation(.calm, value: value)
    }
}

private struct ChipContainer: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(iOS 26, macCatalyst 26, *) {
            content
        } else {
            content
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(reduceTransparency ? AnyShapeStyle(Palette.card) : AnyShapeStyle(.thinMaterial), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        }
    }
}

struct Eyebrow: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .tracking(1.1)
            .foregroundStyle(color)
    }
}
