import SwiftUI
import UIKit
import UserNotifications

// MARK: - App

final class AppDelegate: NSObject, UIApplicationDelegate {
    let notificationDelegate = NotificationDelegate()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        return true
    }
}

@main
struct AccountableApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()
    @State private var drawers = DrawerCenter()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(drawers)
                .tint(Palette.ember)
                .onAppear { MacWindow.configure() }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        store.refresh()
                        if let url = AppRoute.take() { NotificationCenter.default.post(name: .accountableRoute, object: url) }
                    case .background:
                        store.saveNow()
                        store.publishWidgets()
                    default: break
                    }
                }
        }
        .commands { AccountableCommands() }
    }
}

// MARK: - Mac window and menu bar

/// Sets a sensible minimum window size when running as the Mac app.
enum MacWindow {
    static func configure() {
        #if targetEnvironment(macCatalyst)
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            ws.sizeRestrictions?.minimumSize = CGSize(width: 520, height: 700)
            ws.titlebar?.titleVisibility = .hidden
        }
        #endif
    }
}

/// Menu bar items and keyboard shortcuts on the Mac (and with a keyboard on iPad).
struct AccountableCommands: Commands {
    private func go(_ path: String) {
        guard let url = URL(string: "\(SharedConfig.scheme)://\(path)") else { return }
        NotificationCenter.default.post(name: .accountableRoute, object: url)
    }

    var body: some Commands {
        CommandMenu("Go") {
            Button("Today") { go("today") }.keyboardShortcut("1", modifiers: .command)
            Button("Work") { go("work") }.keyboardShortcut("2", modifiers: .command)
            Button("Focus") { go("focus") }.keyboardShortcut("3", modifiers: .command)
            Button("Progress") { go("progress") }.keyboardShortcut("4", modifiers: .command)
            Divider()
            Button("Brain dump") { go("dump") }.keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Start a 5-minute focus") { go("focus?minutes=5") }.keyboardShortcut("f", modifiers: [.command, .shift])
        }
    }
}

// MARK: - Root

enum AppTab: Hashable { case today, work, focus, progress }

enum AppSheet: String, Identifiable {
    case shop, settings
    var id: String { rawValue }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(DrawerCenter.self) private var drawers
    @State private var tab: AppTab = .today
    @State private var sheet: AppSheet? = nil
    @State private var showSplash = true
    @Namespace private var sessionNS

    var body: some View {
        @Bindable var store = store
        ZStack {
            if store.data.onboarded {
                tabs
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: store.data.onboarded)
        .overlay { PopupHost() }
        .overlay { DrawerHost() }
        .overlay { ConfettiLayer(trigger: store.confetti).ignoresSafeArea() }
        .overlay {
            if showSplash {
                SplashView { showSplash = false }
            }
        }
        .environment(\.sessionNamespace, sessionNS)
        .fullScreenCover(item: $store.sessionRequest) { cfg in
            SessionView(config: cfg, checklist: !store.data.prework.isEmpty && !cfg.recovery && !cfg.quick)
                .environment(store)
                .zoomDestination(sessionNS)
                .interactiveDismissDisabled()
        }
        .sheet(item: $sheet, onDismiss: { store.promotePendingSession() }) { s in
            Group {
                switch s {
                case .shop: ShopView()
                case .settings: SettingsView()
                }
            }
            .environment(store)
            .environment(drawers)
        }
        .sensoryFeedback(.selection, trigger: tab)
        .onOpenURL { url in
            showSplash = false
            handle(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountableRoute)) { note in
            if let url = note.object as? URL {
                _ = AppRoute.take()
                handle(url)
            }
        }
        .onAppear {
            // Nothing is running at launch, so clear any timer left from a session that didn't end cleanly.
            if store.sessionRequest == nil { FocusLive.endAll() }
            if let url = AppRoute.take() { handle(url) }
        }
    }

    private var tabs: some View {
        @Bindable var store = store
        return TabView(selection: $tab) {
            NavigationStack { TodayView(goToFocus: { tab = .focus }, goToWork: { tab = .work }).statusToolbar(sheet: $sheet) }
                .centeredTab()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(AppTab.today)
            NavigationStack { WorkView().statusToolbar(sheet: $sheet) }
                .centeredTab()
                .tabItem { Label("Work", systemImage: "checklist") }
                .tag(AppTab.work)
            FocusTab()
                .tabItem { Label("Focus", systemImage: "timer") }
                .tag(AppTab.focus)
            NavigationStack { ProgressTab().statusToolbar(sheet: $sheet) }
                .centeredTab()
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
                .tag(AppTab.progress)
        }
        .fullScreenCover(isPresented: $store.showBrainDump) {
            BrainDumpView()
                .environment(store)
        }
    }

    /// Links from widgets, controls, Siri and notifications:
    /// accountable://focus?minutes=5&task=ID, accountable://dump, accountable://today, accountable://progress.
    private func handle(_ url: URL) {
        guard url.scheme == SharedConfig.scheme, store.data.onboarded else { return }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
        switch url.host ?? "" {
        case "focus":
            guard store.sessionRequest == nil else { return }       // already focusing
            sheet = nil
            store.showBrainDump = false
            let task = value("task").flatMap(UUID.init(uuidString:)).flatMap { tid in store.openTasks.first { $0.id == tid } }
            let minutes = value("minutes").flatMap(Int.init)
            if task != nil || minutes != nil {
                let cfg = SessionConfig(taskID: task?.id ?? store.upNext?.id, minutes: minutes ?? store.data.defaultMinutes, quick: minutes != nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { store.sessionRequest = cfg }
            } else {
                tab = .focus
            }
        case "dump":
            guard store.sessionRequest == nil else { return }
            sheet = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { store.showBrainDump = true }
        case "progress": tab = .progress
        case "work": tab = .work
        default: tab = .today
        }
    }
}

// MARK: - Toolbar

private struct StatusToolbar: ViewModifier {
    @Environment(AppStore.self) private var store
    @Environment(DrawerCenter.self) private var drawers
    @Binding var sheet: AppSheet?

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    drawers.present { StreakDrawer() }
                } label: {
                    StatChip(icon: "flame.fill", value: store.streak, color: Palette.ember, dim: !store.doneToday)
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel("\(store.streak)-day streak")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if store.boostActive {
                    Image(systemName: "bolt.circle.fill")
                        .foregroundStyle(Palette.spark)
                        .symbolEffect(.pulse)
                        .accessibilityLabel("Double XP active")
                }
                Button { sheet = .shop } label: {
                    StatChip(icon: "sparkle", value: store.data.sparks, color: Palette.spark)
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel("\(store.data.sparks) sparks, open shop")
                Button {
                    drawers.present { ShieldsDrawer() }
                } label: {
                    StatChip(icon: "shield.lefthalf.filled", value: store.data.shields, color: Palette.shield)
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel("\(store.data.shields) shields")
                Button { sheet = .settings } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel("Settings")
            }
        }
    }
}

extension View {
    func statusToolbar(sheet: Binding<AppSheet?>) -> some View { modifier(StatusToolbar(sheet: sheet)) }
}

// MARK: - Popups

struct PopupHost: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let p = store.popups.first {
                if p.kind.isBanner {
                    Banner(popup: p)
                        .id(p.id)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                } else {
                    Color.black.opacity(0.35).ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture { }
                    Celebration(popup: p)
                        .id(p.id)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .scale(scale: 0.96).combined(with: .opacity)))
                }
            }
        }
        .animation(.drawer, value: store.popups.first?.id)
    }
}

/// Notification-style banner that drops in from the top. Swipe it up to dismiss early.
private struct Banner: View {
    @Environment(AppStore.self) private var store
    let popup: Popup
    @State private var drag: CGFloat = 0

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .symbolEffect(.bounce, value: popup.id)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
            .padding(.horizontal, 12)
            .offset(y: drag)
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { v in
                        let dy = v.translation.height
                        drag = dy < 0 ? dy : Motion.rubberband(dy, dimension: 120)
                    }
                    .onEnded { v in
                        if drag + Motion.project(v.velocity.height) < -40 {
                            store.popPopup()
                        } else {
                            withAnimation(Motion.handoff(velocity: v.velocity.height, distance: -drag, bounce: 0.2)) { drag = 0 }
                        }
                    }
            )
            .onTapGesture { store.popPopup() }
            Spacer()
        }
        .padding(.top, 4)
        .task {
            switch popup.kind {
            case .quest, .pledgeDone, .dailyGoal, .personalBest:
                Haptics.shared.sparkle()
                SoundFX.shared.play(.quest)
            case .freezeUsed:
                Haptics.shared.play(.success)
            default:
                break
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if store.popups.first?.id == popup.id { store.popPopup() }
        }
    }

    private var icon: String {
        switch popup.kind {
        case .quest: return "checkmark.seal.fill"
        case .shieldLost: return "shield.slash.fill"
        case .freezeUsed: return "snowflake"
        case .dailyGoal: return "target"
        case .pledgeDone: return "scope"
        case .personalBest: return "medal.fill"
        default: return "sparkle"
        }
    }

    private var color: Color {
        switch popup.kind {
        case .quest, .pledgeDone, .personalBest: return Palette.good
        case .shieldLost: return Palette.bad
        case .freezeUsed: return Palette.shield
        case .dailyGoal: return Palette.xp
        default: return Palette.spark
        }
    }

    private var title: String {
        switch popup.kind {
        case .quest(_, let sparks): return "Quest complete · +\(sparks) sparks"
        case .shieldLost: return "A shield cracked"
        case .freezeUsed(let n): return n == 1 ? "Streak freeze used" : "\(n) streak freezes used"
        case .dailyGoal(let g): return "Daily goal reached · \(g) XP"
        case .pledgeDone: return "You did your one thing · +50 XP"
        case .personalBest: return "New personal best"
        default: return ""
        }
    }

    private var detail: String {
        switch popup.kind {
        case .quest(let t, _): return t
        case .shieldLost(let reason): return reason
        case .freezeUsed: return "Your streak is safe. Pick up where you left off."
        case .dailyGoal: return "Everything from here is a bonus."
        case .pledgeDone: return "That's the thing that mattered most today."
        case .personalBest(let text): return text
        default: return ""
        }
    }
}

private struct Celebration: View {
    @Environment(AppStore.self) private var store
    let popup: Popup
    @State private var shown = false
    @State private var flipped = false

    var body: some View {
        VStack(spacing: 14) {
            content
            Button { primary() } label: { Text(primaryLabel) }
                .buttonStyle(GlowButtonStyle())
                .padding(.top, 6)
            if case .loot = popup.kind, store.undoable != nil {
                Button("Oops, not done yet") {
                    store.undoFinish()
                    store.popPopup()
                    Haptics.shared.play(.soft)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(height: 36)
            }
            if case .welcomeBack(_, let lost) = popup.kind, lost > 0, store.canRepair {
                Button("Restore my \(lost)-day streak · \(store.repairCost) sparks") {
                    if store.repairStreak() { store.popPopup() } else {
                        Haptics.shared.play(.error); SoundFX.shared.play(.error)
                    }
                }
                .buttonStyle(SoftButtonStyle(color: Palette.ember))
                .disabled(store.data.sparks < store.repairCost)
            }
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 30, y: 12)
        .padding(.horizontal, 20)
        .blur(radius: shown ? 0 : 8)
        .onAppear {
            withAnimation(.reward) { shown = true }
            celebrate()
        }
    }

    private var primaryLabel: String {
        switch popup.kind {
        case .welcomeBack: return "Find my next step"
        case .loot: return "Collect"
        default: return "Continue"
        }
    }

    private func primary() {
        if case .loot = popup.kind { store.undoable = nil }
        store.popPopup()
    }

    private func celebrate() {
        switch popup.kind {
        case .levelUp:
            Haptics.shared.fanfare(steps: 8); SoundFX.shared.play(.levelUp); store.confetti += 1
        case .loot(_, let r, _, _):
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { flipped = true }
                Haptics.shared.sparkle(count: 6 + r.rawValue * 3)
                SoundFX.shared.play(.loot(r.rawValue))
                if r.rawValue >= 2 { store.confetti += 1 }
            }
        case .allQuests, .streakMilestone:
            Haptics.shared.fanfare(); SoundFX.shared.play(.streak); store.confetti += 1
        case .achievement:
            Haptics.shared.fanfare(steps: 5); SoundFX.shared.play(.quest)
        case .welcomeBack:
            Haptics.shared.play(.soft); SoundFX.shared.play(.pop)
        default:
            break
        }
    }

    @ViewBuilder private var content: some View {
        switch popup.kind {
        case .levelUp(let level):
            LevelMark(level: level, size: 96)
            Text("Level \(level)").font(.largeTitle.weight(.bold))
            Text("\(AppStore.title(for: level)) · \(AppStore.xpFor(level: level + 1) - AppStore.xpFor(level: level)) XP to the next level")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

        case .loot(let title, let r, let xp, let sparks):
            Eyebrow(text: "Task finished · loot drop")
            LootCard(rarity: r, flipped: flipped)
            Text(title).font(.headline).multilineTextAlignment(.center).lineLimit(2)
            HStack(spacing: 16) {
                Label("+\(xp) XP", systemImage: "bolt.fill").foregroundStyle(Palette.xp)
                Label("+\(sparks)", systemImage: "sparkle").foregroundStyle(Palette.spark)
            }
            .font(.headline)
            .opacity(flipped ? 1 : 0)

        case .allQuests:
            Image(systemName: "gift.fill").font(.system(size: 64)).foregroundStyle(Palette.brand)
                .symbolEffect(.bounce, value: shown)
            Text("All quests done").font(.title.weight(.bold))
            Text("+30 sparks and double XP for 15 minutes. A session now counts twice.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

        case .achievement(let title, let icon, let tier, let detail):
            AchievementMark(icon: icon, color: Palette.ember, tier: tier, size: 84)
            Text(title).font(.title.weight(.bold))
            Text("Level \(tier) · \(detail)").font(.subheadline).foregroundStyle(.secondary)

        case .streakMilestone(let n):
            Image(systemName: "flame.fill").font(.system(size: 72)).foregroundStyle(Palette.brand)
                .symbolEffect(.bounce, value: shown)
            Text("\(n) days in a row").font(.largeTitle.weight(.bold)).multilineTextAlignment(.center)
            Text(n >= 100 ? "This is who you are now." : "That's a habit forming.").font(.subheadline).foregroundStyle(.secondary)

        case .welcomeBack(let away, let lost):
            Image(systemName: "hand.wave.fill").font(.system(size: 60)).foregroundStyle(Palette.brand)
                .symbolEffect(.bounce, value: shown)
            Text("Welcome back").font(.largeTitle.weight(.bold))
            Text(lost > 0
                 ? "Your \(store.data.totalXP) XP and Level \(store.level) are all still here. Let's find your next step."
                 : (away > 1 ? "It's been \(away) days. Everything's where you left it. Let's find your next step." : "Let's find your next step."))
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

        default:
            EmptyView()
        }
    }
}

// MARK: - Shared marks

struct LevelMark: View {
    let level: Int
    var size: CGFloat = 56
    var progress: Double? = nil

    var body: some View {
        ZStack {
            if let progress {
                Ring(progress: progress, lineWidth: size * 0.09, color: Palette.ember)
            } else {
                Circle().fill(Palette.brand)
            }
            VStack(spacing: -2) {
                Text("\(level)")
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundStyle(progress == nil ? Color.white : Color.primary)
                    .contentTransition(.numericText(value: Double(level)))
                Text("LEVEL")
                    .font(.system(size: size * 0.12, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(progress == nil ? Color.white.opacity(0.85) : Color.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

struct LootCard: View {
    let rarity: Rarity
    let flipped: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(hex: 0x1C1C24))
                .overlay(Image(systemName: "questionmark").font(.system(size: 44, weight: .bold)).foregroundStyle(.white.opacity(0.3)))
                .opacity(flipped ? 0 : 1)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [rarity.color, rarity.color.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles").font(.system(size: 46, weight: .semibold)).foregroundStyle(.white)
                        Text(rarity.name.uppercased()).font(.headline).tracking(2).foregroundStyle(.white)
                    }
                )
                .shadow(color: rarity.color.opacity(0.6), radius: flipped ? 22 : 0)
                .opacity(flipped ? 1 : 0)
                .scaleEffect(x: -1, y: 1)
        }
        .frame(width: 140, height: 176)
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
    }
}

struct AchievementMark: View {
    let icon: String
    let color: Color
    let tier: Int
    var size: CGFloat = 52

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(tier > 0 ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Palette.track))
                .frame(width: size, height: size)
                .overlay(Image(systemName: icon).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(tier > 0 ? Color.white : Color.secondary))
            if tier > 0 {
                Text("\(tier)")
                    .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.36, height: size * 0.36)
                    .background(Circle().fill(Color.black.opacity(0.75)))
                    .offset(x: size * 0.08, y: size * 0.08)
            }
        }
    }
}
