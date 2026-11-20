import SwiftUI
import Charts

// MARK: - Progress tab

struct ProgressTab: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header.riseIn(0)
                statsGrid.riseIn(0.06)
                records.riseIn(0.12)
                xpChart.riseIn(0.18)
                QuestsCard().riseIn(0.24)
                monthBadge.riseIn(0.3)
                achievements.riseIn(0.36)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background { AppBackground() }
        .navigationTitle("Progress")
    }

    /// Who you are and how close the next level is. The bar never starts empty: it shows progress already made.
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                LevelMark(level: store.level, size: 76, progress: store.levelProgress)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.data.name).font(.title2.weight(.bold)).tracking(-0.3)
                    Text(store.levelTitle).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ember)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                Bar(value: store.levelProgress, color: Palette.ember, height: 8)
                HStack {
                    Text("Level \(store.level)").font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(store.xpToNextLevel) XP to go")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(store.xpToNextLevel)))
                }
            }
        }
        .card(20)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Palette.ember.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .center))
                .allowsHitTesting(false)
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            StatTile(icon: "flame.fill", color: Palette.ember, value: "\(store.streak)", label: "Day streak")
            StatTile(icon: "trophy.fill", color: Palette.xp, value: "\(store.data.bestStreak)", label: "Best streak")
            StatTile(icon: "bolt.fill", color: Palette.xp, value: "\(store.data.totalXP)", label: "Total XP")
            StatTile(icon: "timer", color: Palette.focus, value: "\(store.totalFocusMinutes / 60)h \(store.totalFocusMinutes % 60)m", label: "Focused")
            StatTile(icon: "checkmark.seal.fill", color: Palette.good, value: "\(store.finishedTasks.count)", label: "Tasks finished")
            StatTile(icon: "chart.line.uptrend.xyaxis", color: Palette.habits, value: "\(store.weekAverage)", label: "7-day focus score")
        }
    }

    /// Mastery, not just activity: your own records, so you can see you're getting better.
    private var records: some View {
        let longest = store.data.sessions.map(\.minutes).max() ?? 0
        let bestXP = store.data.days.values.map(\.xp).max() ?? 0
        let bestTasks = store.data.days.values.map(\.tasksDone).max() ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            Text("Personal bests").font(.headline)
            HStack(spacing: 10) {
                recordCell(value: longest > 0 ? "\(longest) min" : "–", label: "Longest focus", icon: "hourglass", color: Palette.focus)
                recordCell(value: bestXP > 0 ? "\(bestXP) XP" : "–", label: "Best day", icon: "bolt.fill", color: Palette.xp)
                recordCell(value: bestTasks > 0 ? "\(bestTasks)" : "–", label: "Tasks in a day", icon: "checkmark.seal.fill", color: Palette.good)
            }
        }
        .card()
    }

    private func recordCell(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(value).font(.system(.headline, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var xpChart: some View {
        let days: [(String, Int)] = (0..<7).reversed().map { back in
            let k = DayKey.add(store.today, -back)
            let d = DayKey.date(k) ?? Date()
            return (d.formatted(.dateTime.weekday(.abbreviated)), store.log(k).xp)
        }
        return VStack(alignment: .leading, spacing: 12) {
            Text("XP this week").font(.headline)
            Chart {
                ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                    BarMark(x: .value("Day", d.0), y: .value("XP", d.1))
                        .foregroundStyle(i == 6 ? AnyShapeStyle(Palette.brand) : AnyShapeStyle(Palette.xp.opacity(0.55)))
                        .cornerRadius(6)
                }
                RuleMark(y: .value("Goal", store.data.dailyGoal))
                    .foregroundStyle(Palette.good)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Goal").font(.caption2.weight(.semibold)).foregroundStyle(Palette.good)
                    }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 170)
        }
        .card()
    }

    private var monthBadge: some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Palette.spark.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Date().formatted(.dateTime.month(.wide))) badge").font(.headline)
                Text("Complete 30 quests this month").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Bar(value: Double(store.monthQuests) / 30, color: Palette.spark, height: 8)
                    Text("\(min(store.monthQuests, 30))/30").font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    private var achievements: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Achievements").font(.headline)
            ForEach(AppStore.achievements) { a in
                let t = store.tier(a)
                let next = t < a.tiers.count ? a.tiers[t] : (a.tiers.last ?? 1)
                let value = a.metric(store)
                HStack(spacing: 14) {
                    AchievementMark(icon: a.icon, color: a.color, tier: t, size: 50)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(a.title).font(.subheadline.weight(.semibold))
                        Bar(value: Double(value) / Double(max(next, 1)), color: a.color, height: 6)
                        Text(t >= a.tiers.count ? "Maxed · \(value) \(a.unit)" : "\(min(value, next)) / \(next) \(a.unit)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .card()
    }
}

private struct StatTile: View {
    let icon: String
    let color: Color
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(.headline, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .card(14)
    }
}

// MARK: - Shop

struct ShopView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var failed = 0
    @State private var bought = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "sparkle").font(.title2).foregroundStyle(Palette.spark)
                            .symbolEffect(.bounce, value: bought)
                        Text("\(store.data.sparks)").font(.system(.title, design: .rounded).weight(.bold)).monospacedDigit()
                            .contentTransition(.numericText(value: Double(store.data.sparks)))
                        Text("sparks").foregroundStyle(.secondary)
                        Spacer()
                    }
                    .modifier(Shake(amount: CGFloat(failed)))
                } footer: {
                    Text("Earn sparks from quests, loot drops and the daily bonus chest.")
                }

                Section("Power-ups") {
                    item("Streak freeze", detail: "Covers one missed day · \(store.data.freezes)/2 equipped", icon: "snowflake",
                         color: Palette.shield, price: store.price(.freeze), disabled: store.data.freezes >= 2) { buy(.freeze) }
                    item("Refill shields", detail: "Back to 5 · you have \(store.data.shields)", icon: "shield.lefthalf.filled",
                         color: Palette.shield, price: store.price(.refill), disabled: store.data.shields >= 5) { buy(.refill) }
                    item("Double XP · 15 min", detail: "Start it right before a session", icon: "bolt.fill",
                         color: Palette.xp, price: store.price(.boost), disabled: false) { buy(.boost) }
                    if store.canRepair, let r = store.data.repair {
                        item("Repair streak", detail: "Bring back your \(r.streak)-day streak · today only", icon: "bandage.fill",
                             color: Palette.ember, price: store.repairCost, disabled: false) {
                            if store.repairStreak() { success() } else { fail() }
                        }
                    }
                }

                Section("Timer colors") {
                    ForEach(TimerTheme.all) { t in
                        let owned = store.data.owned.contains(t.id)
                        Button {
                            if owned {
                                withAnimation(.calm) { store.data.theme = t.id }
                                Haptics.shared.play(.medium)
                            } else {
                                buy(.theme(t.id))
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Circle().fill(t.gradient).frame(width: 30, height: 30)
                                Text(t.name).foregroundStyle(.primary)
                                Spacer()
                                if store.data.theme == t.id {
                                    Image(systemName: "checkmark").foregroundStyle(Palette.ember).fontWeight(.semibold)
                                } else if owned {
                                    Text("Use").foregroundStyle(.secondary)
                                } else {
                                    PriceTag(price: t.price)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Shop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sensoryFeedback(.success, trigger: bought)
            .sensoryFeedback(.error, trigger: failed)
        }
    }

    private func item(_ title: String, detail: String, icon: String, color: Color, price: Int, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if disabled { Text("Full").foregroundStyle(.secondary) } else { PriceTag(price: price) }
            }
        }
        .disabled(disabled)
    }

    private func buy(_ p: AppStore.Purchase) {
        if store.buy(p) { success() } else { fail() }
    }

    private func success() {
        bought += 1
        store.confetti += 1
        Haptics.shared.sparkle()
        SoundFX.shared.play(.purchase)
    }

    private func fail() {
        withAnimation(.linear(duration: 0.4)) { failed += 1 }
        SoundFX.shared.play(.error)
    }
}

private struct PriceTag: View {
    let price: Int
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkle")
            Text("\(price)").monospacedDigit()
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Palette.spark)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Palette.spark.opacity(0.12), in: Capsule())
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("sound") private var sound = true
    @AppStorage("haptics") private var haptics = true
    @State private var importText = ""
    @State private var importMsg = ""
    @State private var confirmReset = false
    @State private var newItem = ""
    @FocusState private var addingItem: Bool

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Name", text: $store.data.name)
                }
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Daily goal").font(.subheadline.weight(.semibold))
                        ChipRow(options: [10, 20, 30, 50, 100], selection: $store.data.dailyGoal) { "\($0) XP" }
                    }
                    .padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default session").font(.subheadline.weight(.semibold))
                        ChipRow(options: [5, 10, 20, 25, 45, 60], selection: $store.data.defaultMinutes) { "\($0)m" }
                    }
                    .padding(.vertical, 4)
                    Toggle("Strict mode", isOn: $store.data.strict)
                } header: {
                    Text("Goals")
                } footer: {
                    Text("Strict mode cracks a shield when you switch apps during a focus round. Locking your phone is always fine.")
                }
                Section {
                    Label("Say \u{201C}Start a focus session in Accountable\u{201D} or \u{201C}Brain dump in Accountable\u{201D}.", systemImage: "mic.badge.plus")
                    Label("Add Start focus or Brain dump to Control Center, the Lock Screen or the Action button.", systemImage: "switch.2")
                    Label("Long-press the Home Screen to add Habits, Tasks or Quick start widgets you can tap.", systemImage: "square.grid.2x2")
                } header: {
                    Text("Siri, controls and widgets")
                }
                .font(.footnote)

                Section("Reminders") {
                    DatePicker("Daily reminder", selection: reminderBinding, displayedComponents: .hourAndMinute)
                    Button("Turn on notifications") { Notifier.requestAuthorization { _ in Notifier.reschedule(store) } }
                }
                Section("Pre-work checklist") {
                    ForEach(Array(store.data.prework.enumerated()), id: \.offset) { _, item in
                        Text(item)
                    }
                    .onDelete { store.data.prework.remove(atOffsets: $0) }
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Palette.ember)
                        TextField("Add a box", text: $newItem)
                            .focused($addingItem)
                            .submitLabel(.done)
                            .onSubmit(addItem)
                    }
                }
                Section("Feel") {
                    Toggle("Sound", isOn: $sound)
                    Toggle("Haptics", isOn: $haptics)
                        .onChange(of: haptics) { _, on in if on { Haptics.shared.play(.success) } }
                }
                Section {
                    TextField("Paste a backup code from the Accountable web page", text: $importText, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.system(size: 13, design: .monospaced))
                    Button("Import") {
                        if let r = store.importBackup(importText) {
                            importMsg = "Imported \(r.tasks) tasks and \(r.habits) habits."
                            importText = ""
                            Haptics.shared.play(.success)
                        } else {
                            importMsg = "That doesn't look like an Accountable backup code."
                            Haptics.shared.play(.error)
                        }
                    }
                    .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !importMsg.isEmpty { Text(importMsg).foregroundStyle(.secondary) }
                } header: {
                    Text("Bring over your web data")
                }
                Section {
                    Button("Run setup again") {
                        store.data.onboarded = false
                        dismiss()
                    }
                    Button("Reset everything", role: .destructive) {
                        Haptics.shared.play(.warning)
                        confirmReset = true
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onDisappear { store.postChange() }
        }
        .overlay {
            Drawer(isPresented: $confirmReset) {
                ConfirmPrompt(title: "Erase everything?",
                              message: "All progress, tasks, habits and streaks will be gone. This can't be undone.",
                              icon: "trash.fill", confirm: "Erase everything",
                              onConfirm: {
                                  confirmReset = false
                                  store.resetEverything()
                                  dismiss()
                              },
                              onCancel: { confirmReset = false })
            }
        }
    }

    private func addItem() {
        let t = newItem.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { addingItem = false; return }
        withAnimation(.calm) { store.data.prework.append(t) }
        newItem = ""
        addingItem = true
        Haptics.shared.play(.light)
    }

    private var reminderBinding: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: store.data.reminderHour, minute: store.data.reminderMinute, second: 0, of: Date()) ?? Date()
        } set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            store.data.reminderHour = c.hour ?? 19
            store.data.reminderMinute = c.minute ?? 30
        }
    }
}

/// Inline choice chips with a sliding selection, used instead of pop-up menus.
struct ChipRow: View {
    let options: [Int]
    @Binding var selection: Int
    let label: (Int) -> String
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { o in
                Button {
                    withAnimation(.calm) { selection = o }
                } label: {
                    Text(label(o))
                        .font(.footnote.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(selection == o ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if selection == o {
                                Capsule().fill(Palette.ember).matchedGeometryEffect(id: "chip", in: ns)
                            }
                        }
                }
                .buttonStyle(PressableStyle(haptic: .tick, scale: 0.92))
                .accessibilityAddTraits(selection == o ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Palette.track, in: Capsule())
    }
}
