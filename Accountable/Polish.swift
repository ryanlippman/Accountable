import SwiftUI

// The 1.4 polish layer: splash, entrance motion, the day rings, empty states and the zoom into a session.
// Everything here follows the same rules as Theme.swift: springs, restraint, Reduce Motion respected.

// MARK: - Spacing

enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

// MARK: - Zoom from the Start button into the session

private struct SessionNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var sessionNamespace: Namespace.ID? {
        get { self[SessionNamespaceKey.self] }
        set { self[SessionNamespaceKey.self] = newValue }
    }
}

extension View {
    /// Marks the view the session screen grows out of (and shrinks back into).
    @ViewBuilder func zoomSource(_ ns: Namespace.ID?) -> some View {
        if let ns { matchedTransitionSource(id: "session", in: ns) } else { self }
    }

    /// The presented session zooms out of the source above. Falls back to the normal cover if the source isn't on screen.
    @ViewBuilder func zoomDestination(_ ns: Namespace.ID?) -> some View {
        if let ns { navigationTransition(.zoom(sourceID: "session", in: ns)) } else { self }
    }
}

// MARK: - One background for every light screen

/// Today, Work and Progress share the same backdrop: the grouped background with a faint warm glow at the top,
/// so moving between tabs feels like one product.
struct AppBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Palette.bg
            LinearGradient(colors: [Palette.ember.opacity(0.10), Palette.rose.opacity(0.03), .clear],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.4))
        }
        .ignoresSafeArea()
    }
}

// MARK: - Entrance motion

/// Cards rise into place, one after another: opacity, offset and a touch of blur travel on the same spring.
struct RiseIn: ViewModifier {
    var delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .scaleEffect(shown || reduceMotion ? 1 : 0.985, anchor: .top)
            .onAppear {
                guard !shown else { return }
                // Critically damped: cards settle, they don't bounce. Reduce Motion gets a plain cross-fade.
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 1).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func riseIn(_ delay: Double = 0) -> some View { modifier(RiseIn(delay: delay)) }
}

// MARK: - Check circle

/// The task checkbox: the outline fills with a springy pop and the tick lands a beat later.
struct CheckCircle: View {
    var on: Bool
    var color: Color = Palette.good
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 2)
                .opacity(on ? 0 : 1)
            Circle()
                .fill(color)
                .scaleEffect(on ? 1 : 0.3)
                .opacity(on ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.42, weight: .heavy))
                .foregroundStyle(.white)
                .scaleEffect(on ? 1 : 0.2)
                .opacity(on ? 1 : 0)
                .animation(.spring(response: 0.38, dampingFraction: 0.6).delay(on ? 0.06 : 0), value: on)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.36, dampingFraction: 0.62), value: on)
    }
}

// MARK: - Day rings

/// Three nested rings, like closing your activity rings: tasks outside, focus in the middle, habits inside.
struct ConcentricRings: View {
    var tasks: Double
    var focus: Double
    var habits: Double
    var lineWidth: CGFloat = 14
    @State private var appeared = false

    var body: some View {
        ZStack {
            layer(tasks, Palette.tasks, inset: 0)
            layer(focus, Palette.focus, inset: lineWidth + 5)
            layer(habits, Palette.habits, inset: (lineWidth + 5) * 2)
        }
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.85).delay(0.2)) { appeared = true }
        }
    }

    private func layer(_ value: Double, _ color: Color, inset: CGFloat) -> some View {
        let p = appeared ? max(0, min(1, value)) : 0
        return ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: p)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(p >= 1 ? 0.55 : 0), radius: 6)
        }
        .padding(inset)
        .animation(.spring(response: 0.9, dampingFraction: 0.9), value: p)
    }
}

/// The top card on Today: the rings, what each one means, and the XP so far.
struct DayHero: View {
    @Environment(AppStore.self) private var store
    let day: String

    var body: some View {
        let sc = store.score(day)
        let log = store.log(day)
        let habitsDone = store.data.habits.filter { log.habits.contains($0.id) }.count
        let closed = [sc.tasksFraction, sc.focusFraction, sc.habitsFraction].filter { $0 >= 1 }.count

        VStack(spacing: 18) {
            HStack(spacing: 22) {
                ZStack {
                    ConcentricRings(tasks: sc.tasksFraction, focus: sc.focusFraction, habits: sc.habitsFraction, lineWidth: 13)
                    VStack(spacing: 0) {
                        // Sized to sit inside the innermost ring with room to breathe.
                        Text("\(sc.total)")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .tracking(-0.4)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(sc.total)))
                        Text("SCORE")
                            .font(.system(size: 7, weight: .heavy))
                            .tracking(1.2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 146, height: 146)

                VStack(alignment: .leading, spacing: 14) {
                    legend("checkmark.seal.fill", Palette.tasks,
                           value: "\(log.tasksDone)", unit: log.tasksDone == 1 ? "task done" : "tasks done")
                    legend("timer", Palette.focus,
                           value: "\(log.focusMinutes)", unit: "min focused")
                    legend("repeat", Palette.habits,
                           value: store.data.habits.isEmpty ? "–" : "\(habitsDone)/\(store.data.habits.count)",
                           unit: store.data.habits.isEmpty ? "no habits yet" : "habits")
                }
                Spacer(minLength: 0)
            }

            HStack {
                Label("\(log.xp) XP", systemImage: "bolt.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.xp)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(log.xp)))
                Spacer()
                Text(closed == 3 ? "All three rings closed" : "7-day average \(store.weekAverage)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(closed == 3 ? Palette.good : Color.secondary)
                    .contentTransition(.opacity)
            }
            .padding(.top, Space.m)
            .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1) }
        }
        .card(20)
        .animation(.calm, value: day)
        .sensoryFeedback(.success, trigger: closed) { old, new in new > old && day == store.today }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Focus score \(sc.total) out of 100. \(log.tasksDone) tasks, \(log.focusMinutes) minutes focused.")
    }

    private func legend(_ icon: String, _ color: Color, value: String, unit: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(color, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Empty state

/// An empty screen should still tell you what to do next.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Palette.ember.opacity(0.12)).frame(width: 80, height: 80)
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Palette.brand)
                    .symbolEffect(.pulse, options: .repeating.speed(0.5))
            }
            Text(title).font(.title3.weight(.bold)).foregroundStyle(.primary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SoftButtonStyle())
                    .frame(maxWidth: 240)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Splash

/// The launch splash: the mark blooms in, a ring draws around it, the name settles, then everything lifts away.
/// Tap to skip. The static launch screen is the same dark color, so there is no flash between the two.
struct SplashView: View {
    var finish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoIn = false
    @State private var ring: CGFloat = 0
    @State private var textIn = false
    @State private var out = false
    @State private var done = false

    var body: some View {
        ZStack {
            Color(hex: 0x0A0A0F)
            RadialGradient(colors: [Palette.ember.opacity(logoIn ? 0.40 : 0), Palette.rose.opacity(logoIn ? 0.16 : 0), .clear],
                           center: .center, startRadius: 0, endRadius: 380)
                .scaleEffect(logoIn ? 1 : 0.6)

            VStack(spacing: 30) {
                ZStack {
                    Circle()
                        .trim(from: 0, to: ring)
                        .stroke(Palette.brand, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 160, height: 160)
                    Image("Mark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 112, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .shadow(color: Palette.rose.opacity(0.55), radius: 32, y: 12)
                        .scaleEffect(logoIn ? 1 : 0.62)
                        .blur(radius: logoIn ? 0 : 14)
                        .opacity(logoIn ? 1 : 0)
                }
                VStack(spacing: 8) {
                    Text("Accountable")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .tracking(-0.5)
                        .foregroundStyle(Palette.nightInk)
                    Text("Start small. Start now.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.nightMuted)
                }
                .opacity(textIn ? 1 : 0)
                .offset(y: textIn || reduceMotion ? 0 : 14)
            }
        }
        .ignoresSafeArea()
        .opacity(out ? 0 : 1)
        .scaleEffect(out && !reduceMotion ? 1.08 : 1)
        .blur(radius: out && !reduceMotion ? 10 : 0)
        .contentShape(Rectangle())
        .onTapGesture { leave() }
        .accessibilityHidden(true)
        .task { await play() }
    }

    private func play() async {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.3)) { logoIn = true; ring = 1; textIn = true }
            try? await Task.sleep(nanoseconds: 900_000_000)
            leave()
            return
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { logoIn = true }
        try? await Task.sleep(nanoseconds: 90_000_000)
        withAnimation(.easeInOut(duration: 0.6)) { ring = 1 }
        try? await Task.sleep(nanoseconds: 160_000_000)
        withAnimation(.spring(response: 0.45, dampingFraction: 1)) { textIn = true }
        try? await Task.sleep(nanoseconds: 520_000_000)
        // The haptic lands with the ring closing, so sight and touch agree.
        Haptics.shared.play(.soft)
        try? await Task.sleep(nanoseconds: 200_000_000)
        leave()
    }

    private func leave() {
        guard !done else { return }
        done = true
        withAnimation(.spring(response: 0.38, dampingFraction: 1)) { out = true }
        Task {
            try? await Task.sleep(nanoseconds: 340_000_000)
            finish()
        }
    }
}
