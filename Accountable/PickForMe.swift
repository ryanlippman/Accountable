import SwiftUI

/// "Pick for me": a reel of your tasks that you spin (button or flick). It slows down like a real
/// wheel, ticking as each task passes, and settles on one. The decision is made; you just start.
struct PickForMeDrawer: View {
    @Environment(AppStore.self) private var store
    @Environment(DrawerCenter.self) private var drawers
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var position: Double = 0      // which row is centered, fractional while moving
    @State private var spinning = false
    @State private var landed: WorkTask? = nil
    @State private var dragStart: Double? = nil
    @State private var spinTask: Task<Void, Never>? = nil

    private let rowHeight: CGFloat = 54

    private var pool: [WorkTask] { Array(store.openTasks.prefix(14)) }

    var body: some View {
        let tasks = pool
        VStack(spacing: 14) {
            DrawerTitle(title: landed == nil ? "Pick for me" : "Do this one",
                        message: landed == nil ? "Spin, or flick the list. Whatever it lands on is the plan." : nil,
                        icon: "dice.fill", iconColor: Palette.spark)
            if tasks.count < 2 {
                Text("Add at least two tasks and I'll choose between them.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else {
                reel(tasks)
                if let t = landed, !spinning {
                    VStack(spacing: 10) {
                        Button {
                            drawers.dismiss()
                            store.sessionRequest = SessionConfig(taskID: t.id, minutes: store.data.defaultMinutes)
                        } label: {
                            Label("Start it", systemImage: "play.fill")
                        }
                        .buttonStyle(GlowButtonStyle(theme: TimerTheme.find(store.data.theme)))
                        HStack(spacing: 10) {
                            Button("Spin again") { spin(velocity: nil) }
                                .buttonStyle(SoftButtonStyle(color: Palette.spark))
                            Button("Make it smaller") {
                                drawers.present { BreakdownDrawer(taskID: t.id) }
                            }
                            .buttonStyle(SoftButtonStyle(color: .secondary))
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Button {
                        spin(velocity: nil)
                    } label: {
                        Label(spinning ? "Spinning…" : "Spin", systemImage: "dice.fill")
                    }
                    .buttonStyle(GlowButtonStyle(tint: Palette.spark))
                    .disabled(spinning)
                }
            }
        }
        .animation(.calm, value: landed?.id)
        .animation(.calm, value: spinning)
        .onDisappear { spinTask?.cancel() }
    }

    // MARK: Reel

    private func reel(_ tasks: [WorkTask]) -> some View {
        let n = tasks.count
        let center = Int(position.rounded())
        return ZStack {
            // Selection band
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(landed != nil && !spinning ? Palette.spark.opacity(0.16) : Palette.track)
                .frame(height: rowHeight)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Palette.spark.opacity(landed != nil && !spinning ? 0.8 : 0), lineWidth: 2))
                .scaleEffect(landed != nil && !spinning ? 1.03 : 1)
                .animation(.reward, value: landed?.id)
            ForEach((center - 2)...(center + 2), id: \.self) { i in
                let t = tasks[((i % n) + n) % n]
                let d = Double(i) - position
                Text(t.title)
                    .font(.system(size: 18, weight: abs(d) < 0.5 ? .bold : .medium))
                    .foregroundStyle(abs(d) < 0.5 ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, minHeight: rowHeight)
                    .scaleEffect(1 - min(0.25, abs(d) * 0.1))
                    .opacity(max(0, 1 - abs(d) * 0.38))
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : -d * 22), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                    .offset(y: CGFloat(d) * rowHeight * 0.92)
            }
        }
        .frame(height: rowHeight * 4)
        .clipped()
        .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { v in
                    guard !spinning else { return }
                    if dragStart == nil { dragStart = position; landed = nil }
                    let new = (dragStart ?? 0) - Double(v.translation.height / rowHeight)
                    if Int(new.rounded()) != Int(position.rounded()) { Haptics.shared.play(.tick) }
                    position = new
                }
                .onEnded { v in
                    dragStart = nil
                    guard !spinning else { return }
                    let vel = -Double(v.velocity.height / rowHeight)
                    if abs(vel) > 3 {
                        spin(velocity: vel)
                    } else {
                        settle(on: tasks)
                    }
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Task reel")
        .accessibilityValue(tasks[((center % n) + n) % n].title)
        .accessibilityAction(named: "Spin") { spin(velocity: nil) }
    }

    // MARK: Physics

    /// Exponential slowdown, like a real wheel: a tick for every task that passes, then a spring onto the winner.
    private func spin(velocity: Double?) {
        let tasks = pool
        guard tasks.count >= 2 else { return }
        spinTask?.cancel()
        landed = nil
        spinning = true
        Haptics.shared.play(.medium)
        if reduceMotion {
            // No long movement: jump straight to a random task.
            let target = Double(Int(position.rounded()) + Int.random(in: 1...tasks.count))
            withAnimation(.easeInOut(duration: 0.25)) { position = target }
            finish(tasks)
            return
        }
        var v = velocity ?? Double.random(in: 22...34)
        let decay = 1.5
        spinTask = Task { @MainActor in
            var last = Date()
            var lastRow = Int(position.rounded())
            while abs(v) > 1.6 && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000)
                let now = Date()
                let dt = now.timeIntervalSince(last)
                last = now
                position += v * dt
                v *= exp(-decay * dt)
                let row = Int(position.rounded())
                if row != lastRow {
                    lastRow = row
                    Haptics.shared.play(.tick)
                }
            }
            guard !Task.isCancelled else { return }
            let target = (v >= 0 ? position.rounded(.up) : position.rounded(.down))
            withAnimation(Motion.handoff(velocity: CGFloat(v), distance: CGFloat(target - position), bounce: 0.35)) {
                position = target
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            finish(tasks)
        }
    }

    private func settle(on tasks: [WorkTask]) {
        withAnimation(.calm) { position = position.rounded() }
    }

    private func finish(_ tasks: [WorkTask]) {
        let n = tasks.count
        let i = ((Int(position.rounded()) % n) + n) % n
        spinning = false
        withAnimation(.reward) { landed = tasks[i] }
        Haptics.shared.play(.success)
        SoundFX.shared.play(.loot(1))
        store.bump("picks")
    }
}
