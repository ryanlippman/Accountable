import SwiftUI
import UIKit

/// A calm, full-screen timer for when the phone is propped up or charging on its side at your desk.
/// It turns itself sideways when the phone does, stays dim on true black, and drifts a few points
/// every minute so nothing burns into the screen.
struct DeskClock: View {
    let session: FocusSession
    let theme: TimerTheme
    let taskTitle: String?
    let close: () -> Void

    @State private var orientation: UIDeviceOrientation = UIDevice.current.orientation
    @State private var chrome = true
    @State private var hideWork: DispatchWorkItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var angle: Double {
        switch orientation {
        case .landscapeLeft: return 90
        case .landscapeRight: return -90
        default: return 0
        }
    }

    var body: some View {
        GeometryReader { geo in
            let sideways = angle != 0
            let w = sideways ? geo.size.height : geo.size.width
            let h = sideways ? geo.size.width : geo.size.height
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                face(now: ctx.date, width: w, height: h, sideways: sideways)
                    .frame(width: w, height: h)
                    .rotationEffect(.degrees(angle))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.6, dampingFraction: 0.9), value: angle)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .contentShape(Rectangle())
        .onTapGesture { showChrome() }
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            orientation = UIDevice.current.orientation
            showChrome()
        }
        .onDisappear { UIDevice.current.endGeneratingDeviceOrientationNotifications() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let o = UIDevice.current.orientation
            if o == .portrait || o == .landscapeLeft || o == .landscapeRight { orientation = o }
        }
    }

    private func face(now: Date, width: CGFloat, height: CGFloat, sideways: Bool) -> some View {
        // Drift a few points each minute.
        let minute = Calendar.current.component(.minute, from: now)
        let drift = CGSize(width: CGFloat((minute * 7) % 13) - 6, height: CGFloat((minute * 5) % 11) - 5)
        let size = min(width * (sideways ? 0.26 : 0.27), height * (sideways ? 0.55 : 0.3))
        return ZStack {
            VStack(spacing: sideways ? 6 : 14) {
                Text(session.phase == .starter ? "JUST BEGIN" : (taskTitle ?? "Focus").uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Color.white.opacity(0.35))
                    .lineLimit(1)
                Text(FocusSession.clock(session.displaySeconds, up: session.countsUp))
                    .font(.system(size: size, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient(colors: [theme.c1.opacity(0.95), theme.c2.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                    .contentTransition(.numericText(countsDown: !session.countsUp))
                    .animation(.snappy(duration: 0.3), value: Int(session.displaySeconds))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(theme.gradient).opacity(0.7)
                            .frame(width: g.size.width * session.progress)
                            .animation(.linear(duration: 1), value: session.progress)
                    }
                }
                .frame(width: min(width * 0.6, 420), height: 3)
                HStack(spacing: 14) {
                    Label(now.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                    if session.combo > 0 { Label("×\(session.combo)", systemImage: "flame.fill") }
                    if session.faceDown { Label("Phone down", systemImage: "iphone.slash") }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
                .labelStyle(.titleAndIcon)
            }
            .offset(reduceMotion ? .zero : drift)
            .animation(.easeInOut(duration: 2), value: minute)

            VStack {
                HStack {
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundStyle(Color.white.opacity(0.6))
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.88))
                    .accessibilityLabel("Close desk clock")
                }
                Spacer()
            }
            .padding(sideways ? 20 : 28)
            .opacity(chrome ? 1 : 0)
            .animation(.easeInOut(duration: 0.4), value: chrome)
        }
    }

    private func showChrome() {
        chrome = true
        hideWork?.cancel()
        let w = DispatchWorkItem { chrome = false }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
    }
}
