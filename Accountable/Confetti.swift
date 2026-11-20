import SwiftUI

/// A short burst of confetti from the bottom corners, drawn on a Canvas.
final class ConfettiSystem {
    struct Piece {
        var x, y, vx, vy, rot, vr, size: Double
        var color: Color
        var shape: Int
        var life: Double
    }

    var pieces: [Piece] = []
    var last: Date? = nil
    var pending = 0

    func burst(_ n: Int = 90) { pending += n }

    func update(_ now: Date, size: CGSize) {
        let dt = min(0.05, now.timeIntervalSince(last ?? now))
        last = now
        if pending > 0 {
            let colors: [Color] = [Palette.ember, Palette.rose, Palette.xp, Palette.habits, Palette.spark, Palette.good]
            let w = Double(size.width), h = Double(size.height)
            for i in 0..<pending {
                let left = i % 2 == 0
                let angle = (left ? -Double.pi / 3 : -2 * Double.pi / 3) + Double.random(in: -0.3...0.3)
                let speed = Double.random(in: 650...1200)
                pieces.append(Piece(x: left ? -10 : w + 10, y: h * 0.9,
                                    vx: cos(angle) * speed, vy: sin(angle) * speed,
                                    rot: Double.random(in: 0...6.28), vr: Double.random(in: -8...8),
                                    size: Double.random(in: 6...11), color: colors[i % colors.count],
                                    shape: i % 2, life: 0))
            }
            pending = 0
        }
        for i in pieces.indices {
            pieces[i].vy += 1400 * dt
            pieces[i].vx *= (1 - 1.5 * dt)
            pieces[i].vy *= (1 - 0.9 * dt)
            pieces[i].x += pieces[i].vx * dt
            pieces[i].y += pieces[i].vy * dt
            pieces[i].rot += pieces[i].vr * dt
            pieces[i].life += dt
        }
        pieces.removeAll { $0.y > Double(size.height) + 40 || $0.life > 4 }
    }

    func draw(_ ctx: inout GraphicsContext) {
        for p in pieces {
            var c = ctx
            c.translateBy(x: CGFloat(p.x), y: CGFloat(p.y))
            c.rotate(by: .radians(p.rot))
            c.opacity = max(0, min(1, 4 - p.life))
            let s = CGFloat(p.size)
            if p.shape == 0 {
                c.fill(Path(roundedRect: CGRect(x: -s / 2, y: -s / 4, width: s, height: s / 2), cornerRadius: 1.5), with: .color(p.color))
            } else {
                c.fill(Path(ellipseIn: CGRect(x: -s / 3, y: -s / 3, width: s / 1.5, height: s / 1.5)), with: .color(p.color))
            }
        }
    }
}

struct ConfettiLayer: View {
    var trigger: Int
    @State private var system = ConfettiSystem()
    @State private var running = false
    @State private var lastBurst = Date.distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !running)) { tl in
            Canvas { ctx, size in
                system.update(tl.date, size: size)
                system.draw(&ctx)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            guard !reduceMotion else { return }
            system.burst()
            system.last = nil
            running = true
            lastBurst = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) {
                if Date().timeIntervalSince(lastBurst) >= 4.1 { running = false }
            }
        }
    }
}
