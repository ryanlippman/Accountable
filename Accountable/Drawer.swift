import SwiftUI
import Observation

/// A bottom card that rises over a dimmed backdrop, used for every prompt in the app instead of system alerts.
///
/// It behaves like a physical object: the card follows your finger 1:1, resists when pulled upward,
/// and on release projects where the flick would land. If that's past the halfway point it leaves
/// at the finger's speed; otherwise it springs home, also at the finger's speed. It can be grabbed
/// again mid-flight, and it always leaves the way it came in.
struct Drawer<Content: View>: View {
    @Binding var isPresented: Bool
    var dark = false
    @ViewBuilder var content: () -> Content

    @State private var drag: CGFloat = 0
    @State private var height: CGFloat = 360
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .bottom) {
            if isPresented {
                Color.black
                    .opacity(dimOpacity)
                    .ignoresSafeArea()
                    .onTapGesture { close(velocity: 0) }
                    .transition(.opacity)
                    .accessibilityHidden(true)
                card
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom))
                    .zIndex(1)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .drawer, value: isPresented)
    }

    private var dimOpacity: Double {
        let base = dark ? 0.55 : 0.32
        return base * Double(max(0, 1 - drag / max(height, 1)))
    }

    private var card: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill((dark ? Color.white : Color.primary).opacity(0.2))
                .frame(width: 38, height: 5)
                .padding(.top, 9)
                .padding(.bottom, 14)
            content()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(dark ? AnyShapeStyle(Palette.nightRaised) : AnyShapeStyle(BackgroundStyle()))
                .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).stroke(dark ? Palette.nightLine : .clear, lineWidth: 1))
                .shadow(color: .black.opacity(dark ? 0.5 : 0.16), radius: 30, y: -2)
                .padding(.bottom, -60)
        }
        .padding(.horizontal, 8)
        .background(GeometryReader { geo in Color.clear.onAppear { height = geo.size.height } })
        .offset(y: drag)
        .gesture(dragGesture)
        .onDisappear { drag = 0 }
        .environment(\.colorScheme, dark ? .dark : scheme)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { v in
                let dy = v.translation.height
                drag = dy >= 0 ? dy : -Motion.rubberband(-dy, dimension: height)
            }
            .onEnded { v in
                let velocity = v.velocity.height
                let landing = drag + Motion.project(velocity)
                if landing > height * 0.45 {
                    close(velocity: velocity)
                } else {
                    withAnimation(Motion.handoff(velocity: velocity, distance: -drag, bounce: 0.15)) { drag = 0 }
                }
            }
    }

    private func close(velocity: CGFloat) {
        Haptics.shared.play(.light)
        if velocity > 0 {
            withAnimation(Motion.handoff(velocity: velocity, distance: height - drag)) { isPresented = false }
        } else {
            isPresented = false
        }
    }
}

// MARK: - App-wide drawer host

/// One drawer at a time for the whole app, shown above the tab bar.
@Observable
final class DrawerCenter {
    var isShown = false
    var dark = false
    @ObservationIgnored private(set) var builder: (() -> AnyView)? = nil
    var token = UUID()

    func present<V: View>(dark: Bool = false, @ViewBuilder _ content: @escaping () -> V) {
        builder = { AnyView(content()) }
        self.dark = dark
        token = UUID()
        isShown = true
    }

    func dismiss() { isShown = false }
}

struct DrawerHost: View {
    @Environment(DrawerCenter.self) private var center

    var body: some View {
        @Bindable var center = center
        Drawer(isPresented: $center.isShown, dark: center.dark) {
            if let b = center.builder {
                b().id(center.token)
            }
        }
    }
}

// MARK: - Building blocks for drawer content

struct DrawerTitle: View {
    let title: String
    var message: String? = nil
    var icon: String? = nil
    var iconColor: Color = Palette.ember

    var body: some View {
        VStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .symbolEffect(.bounce, options: .nonRepeating, value: title)
                    .padding(.bottom, 2)
            }
            Text(title)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 18)
    }
}

/// A text field styled to sit inside a drawer, focused as soon as it appears.
struct DrawerField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(1...3)
            .font(.body)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Palette.track, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .focused($focused)
            .submitLabel(.done)
            .onSubmit(onSubmit)
            .onChange(of: text) { _, new in
                if new.contains("\n") {
                    text = new.replacingOccurrences(of: "\n", with: "")
                    onSubmit()
                }
            }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true } }
    }
}
