import Foundation
import Observation
import SwiftUI
import WidgetKit

@Observable
final class AppStore {
    var data: AppData
    var popups: [Popup] = []
    var sessionRequest: SessionConfig? = nil
    var confetti = 0
    /// Set while the loot popup for a just-finished task is up, so it can be taken back.
    var undoable: UndoInfo? = nil
    var showBrainDump = false
    /// How the brain dump screen should start: listening, the document camera, or the screenshot picker.
    var dumpStart: DumpStart = .voice

    enum DumpStart { case voice, scan, screenshots, photos }

    @ObservationIgnored var pendingSession: SessionConfig? = nil
    /// The running round (start, end, title), shown by the StandBy timer widget.
    @ObservationIgnored var focusForWidget: (start: Date, end: Date, title: String, up: Bool)? = nil
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private var widgetWork: DispatchWorkItem?
    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("accountable.json")
        data = AppStore.load(from: fileURL)
        observeForSave()
        observeWidgetActions()
        refresh()
    }

    // MARK: Persistence

    /// Saves shortly after any change to `data`, however deep, and refreshes the widgets.
    private func observeForSave() {
        withObservationTracking {
            _ = self.data
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.scheduleSave()
                self?.observeForSave()
            }
        }
    }

    private static func load(from url: URL) -> AppData {
        guard let raw = try? Data(contentsOf: url) else { return AppData() }
        if let d = try? JSONDecoder().decode(AppData.self, from: raw) { return d }
        // A save from an older version: fill in any missing fields from the defaults.
        if let saved = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
           let defRaw = try? JSONEncoder().encode(AppData()),
           var merged = try? JSONSerialization.jsonObject(with: defRaw) as? [String: Any] {
            for (k, v) in saved where merged[k] != nil { merged[k] = v }
            if let m = try? JSONSerialization.data(withJSONObject: merged),
               let d = try? JSONDecoder().decode(AppData.self, from: m) { return d }
        }
        let backup = url.deletingLastPathComponent().appendingPathComponent("accountable-unreadable-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: url, to: backup)
        return AppData()
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)

        widgetWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.publishWidgets() }
        widgetWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: w)
    }

    func saveNow() {
        saveWork?.cancel()
        guard let raw = try? JSONEncoder().encode(data) else { return }
        try? raw.write(to: fileURL, options: .atomic)
    }

    // MARK: Days

    var today: String { DayKey.today }
    func log(_ k: String) -> DayLog { data.days[k] ?? DayLog() }
    var todayLog: DayLog { log(today) }

    func editDay(_ k: String, _ change: (inout DayLog) -> Void) {
        var d = data.days[k] ?? DayLog()
        change(&d)
        data.days[k] = d
    }

    func bump(_ stat: String, by n: Int = 1) { data.stats[stat, default: 0] += n }
    func stat(_ s: String) -> Int { data.stats[s] ?? 0 }

    // MARK: Focus score

    func score(_ k: String) -> DayScore {
        let d = log(k)
        let taskValue = Double(d.focusedTasksDone) + Double(max(0, d.tasksDone - d.focusedTasksDone)) * 0.5
        let tF = taskValue > 0 ? 1 - exp(-Foundation.log(4.0) * taskValue / 1.5) : 0
        let target = Double(max(30, data.defaultMinutes * 2))
        let fF = min(1, Double(d.focusMinutes) / target)
        let hF: Double
        if data.habits.isEmpty {
            hF = d.sessions > 0 ? 1 : 0
        } else {
            hF = Double(data.habits.filter { d.habits.contains($0.id) }.count) / Double(data.habits.count)
        }
        let t = Int((45 * tF).rounded()), f = Int((30 * fF).rounded()), h = Int((25 * hF).rounded())
        return DayScore(total: t + f + h, tasks: t, focus: f, habits: h, tasksFraction: tF, focusFraction: fF, habitsFraction: hF)
    }

    var weekAverage: Int {
        let vals = (0..<7).map { score(DayKey.add(today, -$0)).total }
        return vals.reduce(0, +) / 7
    }

    // MARK: Levels

    static func xpFor(level L: Int) -> Int { 40 * (L - 1) * L }

    var level: Int {
        var L = 1
        while AppStore.xpFor(level: L + 1) <= data.totalXP { L += 1 }
        return L
    }

    var levelProgress: Double {
        let a = AppStore.xpFor(level: level), b = AppStore.xpFor(level: level + 1)
        return Double(data.totalXP - a) / Double(max(1, b - a))
    }

    var xpToNextLevel: Int { AppStore.xpFor(level: level + 1) - data.totalXP }

    static let titles: [(Int, String)] = [(1, "Getting Started"), (3, "Starter"), (5, "Steady"), (8, "Locked In"), (12, "Deep Worker"),
                                          (16, "Machine"), (20, "Unstoppable"), (25, "Mastermind"), (30, "Legend"), (40, "Mythic")]
    static func title(for level: Int) -> String { titles.last(where: { $0.0 <= level })?.1 ?? "Getting Started" }
    var levelTitle: String { AppStore.title(for: level) }

    var boostActive: Bool { (data.boostUntil ?? .distantPast) > Date() }

    // MARK: Streak

    func extends(_ k: String) -> Bool { log(k).sessions > 0 }
    func keeps(_ k: String) -> Bool { let d = log(k); return d.sessions > 0 || d.frozen }

    func streakEnding(at end: String) -> Int {
        var k = end, n = 0, guardCount = 0
        while keeps(k) && guardCount < 4000 {
            if extends(k) { n += 1 }
            k = DayKey.add(k, -1)
            guardCount += 1
        }
        return n
    }

    var streak: Int {
        keeps(today) ? streakEnding(at: today) : streakEnding(at: DayKey.add(today, -1))
    }

    var doneToday: Bool { extends(today) }

    /// Missed days get covered by streak freezes. Otherwise the person is welcomed back, and can repair
    /// the streak for that day only. Their XP, level and history never reset.
    private func settleReturn() {
        let t = today
        let last = data.lastActiveDay
        defer {
            if data.lastActiveDay != t { data.activeDays += 1 }
            data.lastActiveDay = t
        }
        guard !last.isEmpty, last != t else { return }
        let away = max(0, Calendar.current.dateComponents([.day], from: DayKey.date(last) ?? Date(), to: DayKey.date(t) ?? Date()).day ?? 0)

        let y = DayKey.add(t, -1)
        var lostStreak = 0
        if !keeps(y) {
            var gap = [y]
            var k = DayKey.add(y, -1)
            var lastKept: String? = nil
            for _ in 0..<90 {
                if keeps(k) { lastKept = k; break }
                gap.append(k)
                k = DayKey.add(k, -1)
            }
            if let lk = lastKept {
                let prev = streakEnding(at: lk)
                if prev > 0 {
                    if gap.count <= data.freezes {
                        for g in gap { editDay(g) { $0.frozen = true } }
                        data.freezes -= gap.count
                        push(.freezeUsed(gap.count))
                    } else if data.lostStreakSeen != lk {
                        data.lostStreakSeen = lk
                        data.repair = RepairOffer(gap: gap, expires: t, streak: prev)
                        lostStreak = prev
                    }
                }
            }
        }
        if away >= 2 || lostStreak > 0 {
            editDay(t) { $0.comeback = true }
            push(.welcomeBack(daysAway: away, lostStreak: lostStreak))
        }
    }

    var repairCost: Int { 400 }
    var canRepair: Bool { (data.repair?.expires ?? "") == today }

    func repairStreak() -> Bool {
        guard let r = data.repair, canRepair, data.sparks >= repairCost else { return false }
        data.sparks -= repairCost
        for g in r.gap { editDay(g) { $0.frozen = true } }
        data.repair = nil
        confetti += 1
        Haptics.shared.fanfare()
        SoundFX.shared.play(.streak)
        postChange()
        return true
    }

    // MARK: Refresh (launch and every return to the app)

    func refresh() {
        if data.shieldsDay != today {
            if !data.shieldsDay.isEmpty && data.shields < 5 { data.shields += 1 }
            data.shieldsDay = today
        }
        if data.onboarded {
            settleReturn()
            checkMissedStarts()
            applyPendingActions()
        }
        postChange()
    }

    private func checkMissedStarts() {
        let now = Date()
        for i in data.tasks.indices {
            let t = data.tasks[i]
            guard t.done == nil, t.planResult == nil, let at = t.plannedStart else { continue }
            if now > at.addingTimeInterval(15 * 60) {
                data.tasks[i].planResult = "missed"
                data.tasks[i].updated = Date()
                loseShield("Missed the start you planned for \(t.title)")
            }
        }
    }

    // MARK: XP, shields, popups

    func push(_ kind: PopupKind) { popups.append(Popup(kind: kind)) }

    func popPopup() {
        guard !popups.isEmpty else { return }
        popups.removeFirst()
    }

    @discardableResult
    func award(_ base: Int) -> Int {
        guard base > 0 else { return 0 }
        let amount = boostActive ? base * 2 : base
        let before = level
        let goalBefore = todayLog.xp >= data.dailyGoal
        data.totalXP += amount
        editDay(today) { $0.xp += amount }
        if level > before { push(.levelUp(level)) }
        if !goalBefore && todayLog.xp >= data.dailyGoal { push(.dailyGoal(data.dailyGoal)) }
        return amount
    }

    func loseShield(_ reason: String) {
        if data.shields > 0 { data.shields -= 1 }
        push(.shieldLost(reason))
        Haptics.shared.heartbreak()
        SoundFX.shared.play(.heartLost)
    }

    /// Run after every change: quests, achievements, reminders and widgets catch up.
    func postChange() {
        checkQuests()
        checkAchievements()
        Notifier.reschedule(self)
    }

    // MARK: Pledge (today's one thing)

    func setPledge(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        editDay(today) { $0.pledge = String(t.prefix(90)); $0.pledgeDone = false }
    }

    func completePledge() {
        guard !todayLog.pledge.isEmpty, !todayLog.pledgeDone else { return }
        editDay(today) { $0.pledgeDone = true }
        bump("pledges")
        award(50)
        push(.pledgeDone)
        postChange()
    }

    func undoPledge() {
        guard todayLog.pledgeDone else { return }
        editDay(today) { $0.pledgeDone = false; $0.xp = max(0, $0.xp - 50) }
        data.totalXP = max(0, data.totalXP - 50)
        bump("pledges", by: -1)
    }

    // MARK: Sessions

    func queueSession(_ c: SessionConfig) { pendingSession = c }

    func promotePendingSession() {
        guard let c = pendingSession else { return }
        pendingSession = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.sessionRequest = c }
    }

    /// Called when the timer actually starts. Returns true when it counts as an on-time planned start.
    func beginSession(_ c: SessionConfig) -> Bool {
        guard let id = c.taskID, let i = data.tasks.firstIndex(where: { $0.id == id }),
              let at = data.tasks[i].plannedStart, data.tasks[i].planResult == nil else { return false }
        let now = Date()
        guard now > at.addingTimeInterval(-30 * 60) else { return false }
        let onTime = now <= at.addingTimeInterval(15 * 60)
        data.tasks[i].planResult = onTime ? "onTime" : "late"
        data.tasks[i].updated = Date()
        if onTime {
            editDay(today) { $0.onTime += 1 }
            bump("onTime")
        }
        Notifier.cancelTask(id)
        return onTime
    }

    func completeSession(_ r: SessionResult) -> SessionReward {
        let k = today
        let firstToday = !extends(k)
        let streakBefore = streak
        let comeback = log(k).comeback && firstToday
        var lines: [(String, Int)] = [("Focus time", r.focusedMinutes), ("Session complete", 10)]
        if comeback { lines.append(("Welcome back", 20)) }
        if r.maxCombo >= 1 { lines.append(("Combo ×\(r.maxCombo)", r.maxCombo * 3)) }
        if r.phoneDownRatio >= 0.8 { lines.append(("Phone face down", max(5, r.focusedMinutes / 2))) }
        if r.distractions == 0 && r.focusedMinutes >= 10 { lines.append(("Zero distractions", 5)) }
        if r.onTime { lines.append(("On-time start", 15)) }
        var raw = lines.reduce(0) { $0 + $1.1 }
        let halved = data.shields == 0 && !r.config.recovery
        if halved { raw /= 2 }
        let boosted = boostActive
        let hour = Calendar.current.component(.hour, from: r.started)
        editDay(k) { d in
            d.sessions += 1
            d.focusMinutes += r.focusedMinutes
            d.maxCombo = max(d.maxCombo, r.maxCombo)
            if hour < 12 { d.earlyStart = true }
            if r.phoneDownRatio >= 0.8 { d.phoneDown += 1 }
        }
        let previousLongest = data.sessions.map(\.minutes).max() ?? 0
        if r.focusedMinutes > previousLongest && previousLongest >= 5 {
            push(.personalBest("Longest focus yet: \(r.focusedMinutes) minutes. Your last record was \(previousLongest)."))
        }
        if hour >= 21 || hour < 4 { bump("night") }
        if r.focusedMinutes >= 45 { bump("long") }
        if comeback { bump("comebacks") }
        bump("sessions")
        let total = award(raw)
        if let id = r.config.taskID, let i = data.tasks.firstIndex(where: { $0.id == id }) {
            data.tasks[i].focusMinutes += r.focusedMinutes
            data.tasks[i].sessions += 1
            data.tasks[i].updated = Date()
        }
        data.sessions.append(SessionRecord(start: r.started, minutes: r.focusedMinutes, xp: total, taskID: r.config.taskID,
                                           distractions: r.distractions, phoneDown: r.phoneDownRatio))
        if data.sessions.count > 1000 { data.sessions.removeFirst(data.sessions.count - 1000) }
        var restored = false
        if r.config.recovery && data.shields < 5 { data.shields += 1; restored = true }
        let after = streak
        if after > data.bestStreak { data.bestStreak = after }
        if firstToday && [3, 7, 14, 21, 30, 50, 75, 100, 150, 200, 250, 300, 365, 500, 1000].contains(after) {
            push(.streakMilestone(after))
        }
        postChange()
        return SessionReward(total: total, lines: lines, halved: halved, boosted: boosted, focusedMinutes: r.focusedMinutes,
                             maxCombo: r.maxCombo, phoneDownRatio: r.phoneDownRatio, distractions: r.distractions,
                             streakBefore: streakBefore, streakAfter: after, firstToday: firstToday,
                             shieldRestored: restored, comeback: comeback)
    }

    // MARK: Tasks

    var openTasks: [WorkTask] {
        data.tasks.filter { $0.done == nil }.sorted { a, b in
            switch (a.plannedStart, b.plannedStart) {
            case let (x?, y?): return x < y
            case (.some, .none): return true
            case (.none, .some): return false
            default: return a.created < b.created
            }
        }
    }

    var finishedTasks: [WorkTask] {
        data.tasks.filter { $0.done != nil }.sorted { ($0.done ?? .distantPast) > ($1.done ?? .distantPast) }
    }

    func isDue(_ t: WorkTask, at now: Date = Date()) -> Bool {
        guard let at = t.plannedStart, t.planResult == nil else { return false }
        return now >= at.addingTimeInterval(-30 * 60) && now <= at.addingTimeInterval(15 * 60)
    }

    /// What to work on next: a start that's due, then the next planned one today, then the oldest open task.
    var upNext: WorkTask? {
        let open = openTasks
        let now = Date()
        if let due = open.first(where: { isDue($0, at: now) }) { return due }
        return open.first { $0.plannedStart.map { Calendar.current.isDateInToday($0) && $0 > now } ?? false } ?? open.first
    }

    @discardableResult
    func addTask(_ title: String, firstStep: String? = nil) -> UUID? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let task = WorkTask(title: String(t.prefix(140)), firstStep: firstStep.flatMap { $0.isEmpty ? nil : String($0.prefix(140)) })
        data.tasks.append(task)
        if task.firstStep != nil { editDay(today) { $0.firstSteps += 1 } }
        postChange()
        return task.id
    }

    func setFirstStep(_ id: UUID, _ step: String) {
        guard let i = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        let s = step.trimmingCharacters(in: .whitespacesAndNewlines)
        let had = data.tasks[i].firstStep != nil
        data.tasks[i].firstStep = s.isEmpty ? nil : String(s.prefix(140))
        data.tasks[i].updated = Date()
        if !had && !s.isEmpty { editDay(today) { $0.firstSteps += 1 } }
        postChange()
    }

    // MARK: Steps (Break it down)

    func setSteps(_ id: UUID, _ titles: [String]) {
        guard let i = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        let clean = titles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let had = data.tasks[i].steps
        data.tasks[i].steps = clean.map { t in had.first(where: { $0.title == t }) ?? Subtask(title: String(t.prefix(120))) }
        data.tasks[i].updated = Date()
        if !clean.isEmpty && had.isEmpty { bump("breakdowns") }
        postChange()
    }

    /// Checking off a step is a small win: a bit of XP and a tick.
    func toggleStep(_ taskID: UUID, _ stepID: UUID) {
        guard let i = data.tasks.firstIndex(where: { $0.id == taskID }),
              let j = data.tasks[i].steps.firstIndex(where: { $0.id == stepID }) else { return }
        data.tasks[i].steps[j].done.toggle()
        data.tasks[i].updated = Date()
        if data.tasks[i].steps[j].done {
            award(3)
            bump("steps")
        } else {
            data.totalXP = max(0, data.totalXP - 3)
            editDay(today) { $0.xp = max(0, $0.xp - 3) }
            bump("steps", by: -1)
        }
        postChange()
    }

    func setDue(_ id: UUID, _ date: Date?) {
        guard let i = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        data.tasks[i].due = date
        data.tasks[i].updated = Date()
    }

    func renameTask(_ id: UUID, _ title: String) {
        guard let i = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        data.tasks[i].title = String(t.prefix(140))
        data.tasks[i].updated = Date()
    }

    func finishTask(_ id: UUID) {
        guard let i = data.tasks.firstIndex(where: { $0.id == id }), data.tasks[i].done == nil else { return }
        let rarity = Rarity.roll()
        let focused = data.tasks[i].focusMinutes > 0
        data.tasks[i].done = Date()
        data.tasks[i].rarity = rarity
        data.tasks[i].updated = Date()
        Notifier.cancelTask(id)
        editDay(today) { d in
            d.tasksDone += 1
            if focused { d.focusedTasksDone += 1 }
        }
        if rarity == .legendary { bump("legendary") }
        let xp = award(15 + (focused ? 15 : 0) + rarity.bonusXP)
        data.sparks += rarity.sparks
        undoable = UndoInfo(taskID: id, xp: xp, sparks: rarity.sparks, focused: focused)
        push(.loot(title: data.tasks[i].title, rarity: rarity, xp: xp, sparks: rarity.sparks))
        postChange()
    }

    /// Takes back the task that was just finished, including the XP and sparks it paid out.
    func undoFinish() {
        guard let u = undoable else { return }
        undoable = nil
        guard let i = data.tasks.firstIndex(where: { $0.id == u.taskID }) else { return }
        data.tasks[i].done = nil
        data.tasks[i].updated = Date()
        data.totalXP = max(0, data.totalXP - u.xp)
        data.sparks = max(0, data.sparks - u.sparks)
        editDay(today) { d in
            d.xp = max(0, d.xp - u.xp)
            d.tasksDone = max(0, d.tasksDone - 1)
            if u.focused { d.focusedTasksDone = max(0, d.focusedTasksDone - 1) }
        }
        postChange()
    }

    func restoreTask(_ id: UUID) {
        guard let i = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        data.tasks[i].done = nil
        data.tasks[i].updated = Date()
        postChange()
    }

    func deleteTask(_ id: UUID) {
        data.tasks.removeAll { $0.id == id }
        Notifier.cancelTask(id)
        postChange()
    }

    func planTask(_ id: UUID, at date: Date?) {
        guard let i = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        data.tasks[i].plannedStart = date
        data.tasks[i].planResult = nil
        data.tasks[i].updated = Date()
        if date != nil {
            editDay(today) { $0.plans += 1 }
            bump("plans")
        }
        postChange()
    }

    /// A tiny, concrete first action for a task, so starting takes no decisions.
    static func tinyStep(for title: String) -> String {
        let t = title.lowercased()
        let rules: [([String], String)] = [
            (["essay", "paper", "write", "report", "draft", "article", "post"], "Open the doc and write one rough sentence"),
            (["read", "chapter", "book", "article"], "Open it and read the first page"),
            (["study", "test", "exam", "quiz", "review", "flashcard"], "Open your notes and review one page"),
            (["homework", "problem", "worksheet", "set", "math", "calc"], "Open it and read the first question"),
            (["email", "reply", "message", "text"], "Open the draft and write the first line"),
            (["clean", "tidy", "room", "laundry", "dishes"], "Put away five things"),
            (["code", "bug", "build", "app", "feature", "project"], "Open the project and write down the very next change"),
            (["slides", "presentation", "deck"], "Make the title slide"),
            (["apply", "application", "form"], "Open the form and fill in your name"),
            (["practice", "piano", "guitar", "workout", "run", "gym"], "Get changed and do the first two minutes")
        ]
        for (keys, step) in rules where keys.contains(where: { t.contains($0) }) { return step }
        return "Spend two minutes on the very first part"
    }

    // MARK: Habits

    func habitDone(_ h: Habit, on k: String? = nil) -> Bool { log(k ?? today).habits.contains(h.id) }

    func habitStreak(_ h: Habit) -> Int {
        var k = habitDone(h) ? today : DayKey.add(today, -1)
        var n = 0
        while log(k).habits.contains(h.id) && n < 3650 { n += 1; k = DayKey.add(k, -1) }
        return n
    }

    func toggleHabit(_ h: Habit) {
        let k = today
        if habitDone(h) {
            editDay(k) { d in d.habits.removeAll { $0 == h.id } }
            let back = min(5, data.totalXP)
            data.totalXP -= back
            editDay(k) { $0.xp = max(0, $0.xp - back) }
            bump("habits", by: -1)
        } else {
            editDay(k) { $0.habits.append(h.id) }
            bump("habits")
            award(5)
        }
        postChange()
    }

    func addHabit(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        data.habits.append(Habit(title: String(t.prefix(80))))
        postChange()
    }

    func deleteHabit(_ id: UUID) {
        data.habits.removeAll { $0.id == id }
        postChange()
    }

    // MARK: Quests

    func quests(for k: String) -> [Quest] {
        let d = log(k)
        let habitsDone = data.habits.filter { d.habits.contains($0.id) }.count
        var pool: [Quest] = [
            Quest(id: "sessions2", title: "Finish 2 focus sessions", icon: "timer", target: 2, progress: d.sessions, sparks: 10),
            Quest(id: "sessions3", title: "Finish 3 focus sessions", icon: "timer", target: 3, progress: d.sessions, sparks: 20),
            Quest(id: "focus45", title: "Focus for 45 minutes", icon: "hourglass", target: 45, progress: d.focusMinutes, sparks: 15),
            Quest(id: "focus90", title: "Focus for 90 minutes", icon: "hourglass.bottomhalf.filled", target: 90, progress: d.focusMinutes, sparks: 25),
            Quest(id: "combo", title: "Reach a ×3 combo", icon: "flame.fill", target: 3, progress: d.maxCombo, sparks: 10),
            Quest(id: "task", title: "Finish a task", icon: "checkmark.seal.fill", target: 1, progress: d.tasksDone, sparks: 10),
            Quest(id: "task2", title: "Finish 2 tasks", icon: "checkmark.seal.fill", target: 2, progress: d.tasksDone, sparks: 20),
            Quest(id: "early", title: "Start a session before noon", icon: "sunrise.fill", target: 1, progress: d.earlyStart ? 1 : 0, sparks: 10),
            Quest(id: "phone", title: "Do a phone-down session", icon: "iphone.slash", target: 1, progress: d.phoneDown, sparks: 10),
            Quest(id: "phone2", title: "Two phone-down sessions", icon: "iphone.slash", target: 2, progress: d.phoneDown, sparks: 20),
            Quest(id: "pledge", title: "Do today's one thing", icon: "scope", target: 1, progress: d.pledgeDone ? 1 : 0, sparks: 15),
            Quest(id: "plan", title: "Plan a start time", icon: "alarm", target: 1, progress: d.plans, sparks: 10),
            Quest(id: "ontime", title: "Start a planned task on time", icon: "clock.badge.checkmark", target: 1, progress: d.onTime, sparks: 15),
            Quest(id: "firststep", title: "Give a task a tiny first step", icon: "shoeprints.fill", target: 1, progress: d.firstSteps, sparks: 10)
        ]
        if !data.habits.isEmpty {
            pool.append(Quest(id: "habits", title: "Check off every habit", icon: "repeat", target: data.habits.count, progress: habitsDone, sparks: 10))
        }
        var rng = SeededRNG(seed: stableHash("quests-" + k))
        pool.shuffle(using: &rng)
        let first: Quest
        if d.comeback {
            first = Quest(id: "back", title: "Welcome back: finish one session", icon: "arrow.uturn.backward.circle.fill", target: 1, progress: d.sessions, sparks: 25)
        } else {
            first = Quest(id: "xp", title: "Earn \(data.dailyGoal * 3) XP", icon: "bolt.fill", target: data.dailyGoal * 3, progress: d.xp, sparks: 10)
        }
        return [first] + Array(pool.prefix(2))
    }

    var todayQuests: [Quest] { quests(for: today) }

    var monthKey: String { String(today.prefix(7)) }
    var monthQuests: Int { data.questsByMonth[monthKey] ?? 0 }

    private func checkQuests() {
        guard data.onboarded else { return }
        let k = today
        let qs = quests(for: k)
        for q in qs where q.done && !log(k).claimed.contains(q.id) {
            editDay(k) { $0.claimed.append(q.id) }
            data.sparks += q.sparks
            data.questsByMonth[monthKey, default: 0] += 1
            push(.quest(title: q.title, sparks: q.sparks))
        }
        let d = log(k)
        if qs.allSatisfy({ d.claimed.contains($0.id) }) && !d.chest {
            editDay(k) { $0.chest = true }
            data.sparks += 30
            data.boostUntil = Date().addingTimeInterval(15 * 60)
            push(.allQuests)
        }
    }

    // MARK: Achievements

    var totalFocusMinutes: Int { data.days.values.reduce(0) { $0 + $1.focusMinutes } }

    static let achievements: [Achievement] = [
        Achievement(id: "wildfire", title: "Wildfire", icon: "flame.fill", color: Color(hex: 0xFF5A2C),
                    tiers: [3, 7, 14, 30, 50, 100, 200, 365], unit: "day streak") { $0.data.bestStreak },
        Achievement(id: "regular", title: "Regular", icon: "calendar", color: Color(hex: 0x0EA5E9),
                    tiers: [3, 10, 30, 60, 100, 200, 365], unit: "days showing up") { $0.data.activeDays },
        Achievement(id: "sage", title: "Sage", icon: "bolt.fill", color: Color(hex: 0xFFB020),
                    tiers: [100, 500, 1000, 2500, 5000, 10000, 25000, 50000], unit: "XP earned") { $0.data.totalXP },
        Achievement(id: "finisher", title: "Finisher", icon: "checkmark.seal.fill", color: Color(hex: 0x1E9E5E),
                    tiers: [1, 5, 10, 25, 50, 100, 250, 500], unit: "tasks finished") { s in s.data.tasks.filter { $0.done != nil }.count },
        Achievement(id: "deep", title: "Deep Diver", icon: "hourglass", color: Color(hex: 0x3E7BFA),
                    tiers: [60, 300, 600, 1200, 3000, 6000, 12000, 30000], unit: "minutes focused") { $0.totalFocusMinutes },
        Achievement(id: "marathon", title: "Marathon", icon: "figure.run", color: Color(hex: 0xE11D48),
                    tiers: [1, 5, 15, 40, 100], unit: "sessions of 45+ min") { $0.stat("long") },
        Achievement(id: "untouchable", title: "Untouchable", icon: "iphone.slash", color: Color(hex: 0x7C5CFF),
                    tiers: [1, 5, 10, 25, 50, 100], unit: "phone-down sessions") { s in s.data.days.values.reduce(0) { $0 + $1.phoneDown } },
        Achievement(id: "ontime", title: "Right On Time", icon: "clock.badge.checkmark", color: Color(hex: 0x14B8A6),
                    tiers: [1, 5, 15, 40, 100], unit: "on-time starts") { $0.stat("onTime") },
        Achievement(id: "planner", title: "Planner", icon: "alarm", color: Color(hex: 0x6366F1),
                    tiers: [1, 10, 30, 75, 150], unit: "starts planned") { $0.stat("plans") },
        Achievement(id: "habit", title: "Habit Hero", icon: "repeat", color: Color(hex: 0x2563EB),
                    tiers: [5, 25, 75, 200, 500, 1000], unit: "habits checked") { $0.stat("habits") },
        Achievement(id: "promise", title: "Promise Keeper", icon: "scope", color: Color(hex: 0xF97316),
                    tiers: [1, 7, 30, 100, 250], unit: "one-things done") { $0.stat("pledges") },
        Achievement(id: "comeback", title: "Comeback", icon: "arrow.uturn.backward.circle.fill", color: Color(hex: 0x22C55E),
                    tiers: [1, 3, 10, 25], unit: "returns after a break") { $0.stat("comebacks") },
        Achievement(id: "earlybird", title: "Early Bird", icon: "sunrise.fill", color: Color(hex: 0xF2A516),
                    tiers: [1, 5, 15, 30, 60, 120], unit: "morning starts") { s in s.data.days.values.filter { $0.earlyStart }.count },
        Achievement(id: "nightowl", title: "Night Owl", icon: "moon.stars.fill", color: Color(hex: 0x4338CA),
                    tiers: [1, 5, 15, 40, 100], unit: "late sessions") { $0.stat("night") },
        Achievement(id: "questmaster", title: "Quest Master", icon: "map.fill", color: Color(hex: 0xFF2D55),
                    tiers: [3, 15, 50, 100, 250, 500], unit: "quests done") { s in s.data.questsByMonth.values.reduce(0, +) },
        Achievement(id: "lucky", title: "Lucky Find", icon: "sparkles", color: Color(hex: 0xF5B021),
                    tiers: [1, 3, 10, 25], unit: "legendary drops") { $0.stat("legendary") },
        Achievement(id: "clearhead", title: "Clear Head", icon: "mic.fill", color: Color(hex: 0xEC4899),
                    tiers: [1, 5, 15, 40, 100], unit: "brain dumps") { $0.stat("dumps") },
        Achievement(id: "builder", title: "Step by Step", icon: "list.bullet.indent", color: Color(hex: 0x0D9488),
                    tiers: [5, 25, 75, 200, 500], unit: "small steps done") { $0.stat("steps") },
        Achievement(id: "collector", title: "Collector", icon: "paintpalette.fill", color: Color(hex: 0xA855F7),
                    tiers: [2, 4, 7, 10, 14], unit: "timer colors") { $0.data.owned.count }
    ]

    func tier(_ a: Achievement) -> Int { a.tiers.filter { a.metric(self) >= $0 }.count }

    private func checkAchievements() {
        guard data.onboarded else { return }
        for a in AppStore.achievements {
            let t = tier(a)
            let seen = data.achievementsSeen[a.id] ?? 0
            if t > seen {
                data.achievementsSeen[a.id] = t
                push(.achievement(title: a.title, icon: a.icon, tier: t, detail: "\(a.tiers[t - 1]) \(a.unit)"))
            }
        }
    }

    // MARK: Shop

    enum Purchase { case freeze, refill, boost, theme(String) }

    func price(_ p: Purchase) -> Int {
        switch p {
        case .freeze: return 200
        case .refill: return 350
        case .boost: return 100
        case .theme(let id): return TimerTheme.find(id).price
        }
    }

    func buy(_ p: Purchase) -> Bool {
        let cost = price(p)
        guard data.sparks >= cost else { return false }
        switch p {
        case .freeze:
            guard data.freezes < 2 else { return false }
            data.freezes += 1
        case .refill:
            guard data.shields < 5 else { return false }
            data.shields = 5
        case .boost:
            let from = max(Date(), data.boostUntil ?? Date())
            data.boostUntil = from.addingTimeInterval(15 * 60)
        case .theme(let id):
            guard !data.owned.contains(id) else { return false }
            data.owned.append(id)
            data.theme = id
        }
        data.sparks -= cost
        postChange()
        return true
    }

    // MARK: Widgets

    func publishWidgets() {
        let t = today
        let sc = score(t)
        let monday = AppStore.mondayOfWeek(t)
        let todayIdx = (Calendar(identifier: .gregorian).component(.weekday, from: Date()) + 5) % 7
        let next = upNext
        let qs = todayQuests.map { WidgetSnapshot.QuestItem(title: $0.title, icon: $0.icon, progress: $0.progress, target: $0.target) }
        var snap = WidgetSnapshot(
            updated: Date(), name: data.name, streak: streak, doneToday: doneToday,
            score: sc.total, scoreTasks: sc.tasks, scoreFocus: sc.focus, scoreHabits: sc.habits,
            xpToday: todayLog.xp, dailyGoal: data.dailyGoal, level: level, levelProgress: levelProgress, levelTitle: levelTitle,
            focusMinutesToday: todayLog.focusMinutes, sessionsToday: todayLog.sessions,
            nextTaskID: next?.id.uuidString, nextTask: next?.title,
            nextStep: next.map { $0.nextAction ?? AppStore.tinyStep(for: $0.title) }, nextStart: next?.plannedStart,
            openTasks: openTasks.count,
            habitsDone: data.habits.filter { todayLog.habits.contains($0.id) }.count, habitsTotal: data.habits.count,
            quests: qs,
            week: (0..<7).map { i in i > todayIdx ? -1 : score(DayKey.add(monday, i)).total },
            weekDone: (0..<7).map { i in extends(DayKey.add(monday, i)) },
            todayIndex: todayIdx, theme: data.theme, freezes: data.freezes)
        snap.habitItems = data.habits.map {
            WidgetSnapshot.HabitItem(id: $0.id.uuidString, title: $0.title, done: habitDone($0), streak: habitStreak($0))
        }
        snap.taskItems = openTasks.prefix(6).map {
            WidgetSnapshot.TaskItem(id: $0.id.uuidString, title: $0.title, step: $0.nextAction ?? AppStore.tinyStep(for: $0.title), start: $0.plannedStart)
        }
        if let f = focusForWidget, f.end > Date() {
            snap.focusStart = f.start
            snap.focusEnd = f.end
            snap.focusTitle = f.title
            snap.focusCountsUp = f.up
        }
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func mondayOfWeek(_ k: String) -> String {
        let d = DayKey.date(k) ?? Date()
        let wd = Calendar(identifier: .gregorian).component(.weekday, from: d)
        return DayKey.add(k, -((wd + 5) % 7))
    }

    // MARK: Import from the web version

    func importBackup(_ text: String) -> (tasks: Int, habits: Int)? {
        guard let raw = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return nil }
        var nt = 0, nh = 0
        let haveTasks = Set(data.tasks.filter { $0.done == nil }.map { $0.title.lowercased() })
        if let tasks = obj["tasks"] as? [String: Any], let items = tasks["items"] as? [[String: Any]] {
            for it in items {
                guard let title = it["title"] as? String, (it["status"] as? String) != "done",
                      !haveTasks.contains(title.lowercased()) else { continue }
                var t = WorkTask(title: title)
                t.focusMinutes = ((it["poms"] as? Int) ?? 0) * 20
                t.firstStep = (it["cueFirst"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                data.tasks.append(t)
                nt += 1
            }
        }
        let haveHabits = Set(data.habits.map { $0.title.lowercased() })
        if let settings = obj["settings"] as? [String: Any], let promises = settings["promises"] as? [[String: Any]] {
            for p in promises {
                guard let label = p["label"] as? String, !label.trimmingCharacters(in: .whitespaces).isEmpty,
                      (p["active"] as? Bool) != false, !haveHabits.contains(label.lowercased()) else { continue }
                data.habits.append(Habit(title: label))
                nh += 1
            }
        }
        guard nt + nh > 0 || obj["tasks"] != nil else { return nil }
        postChange()
        return (nt, nh)
    }

    func resetEverything() {
        data = AppData()
        popups = []
        Notifier.removeAll()
    }

    // MARK: Widgets, Siri and Shortcuts

    private func observeWidgetActions() {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
            DispatchQueue.main.async { NotificationCenter.default.post(name: .accountableActions, object: nil) }
        }, ActionQueue.darwinName as CFString, nil, .deliverImmediately)
        NotificationCenter.default.addObserver(forName: .accountableActions, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.data.onboarded else { return }
            self.applyPendingActions()
        }
    }

    /// Applies taps from widgets and requests from Siri. Each action is idempotent, so applying one twice is harmless.
    func applyPendingActions() {
        let actions = ActionQueue.drain()
        guard !actions.isEmpty else { return }
        for a in actions {
            switch a {
            case .setHabit(let id, let done):
                if let h = data.habits.first(where: { $0.id.uuidString == id }), habitDone(h) != done { toggleHabit(h) }
            case .finishTask(let id):
                if let u = UUID(uuidString: id) { finishTask(u) }
            case .addTask(let title):
                addTask(title, firstStep: AppStore.tinyStep(for: title))
            }
        }
        publishWidgets()
    }
}
