import Foundation
import SwiftUI

// Code shared by the app and its widgets: brand colors, timer themes and the snapshot the app writes for widgets.

enum SharedConfig {
    static let appGroup = "group.com.ryanlippman.accountable"
    static let snapshotKey = "widgetSnapshot.v1"
    static let scheme = "accountable"
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

enum Brand {
    static let ember = Color(hex: 0xFF5A2C)
    static let rose = Color(hex: 0xFF2D55)
    static let tasks = Color(hex: 0xF2A516)
    static let focus = Color(hex: 0xFF5A3C)
    static let habits = Color(hex: 0x3E7BFA)
    static let xp = Color(hex: 0xFFB020)
    static let good = Color(hex: 0x1E9E5E)
    static let gradient = LinearGradient(colors: [Color(hex: 0xFF7A45), Color(hex: 0xFF2D55)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Timer colors. Ember is free; the rest are unlocked with sparks.
struct TimerTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let hex1: UInt32
    let hex2: UInt32
    let price: Int

    var c1: Color { Color(hex: hex1) }
    var c2: Color { Color(hex: hex2) }
    var gradient: LinearGradient { LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing) }

    static let all: [TimerTheme] = [
        TimerTheme(id: "ember", name: "Ember", hex1: 0xFF7A45, hex2: 0xFF2D55, price: 0),
        TimerTheme(id: "gold", name: "Gold", hex1: 0xFFC93C, hex2: 0xFF8A00, price: 200),
        TimerTheme(id: "sunset", name: "Sunset", hex1: 0xFFB36B, hex2: 0xE0457B, price: 200),
        TimerTheme(id: "rose", name: "Rose", hex1: 0xFF8FB1, hex2: 0xE0216B, price: 250),
        TimerTheme(id: "ocean", name: "Ocean", hex1: 0x4FC3FF, hex2: 0x4F6BFF, price: 250),
        TimerTheme(id: "ice", name: "Glacier", hex1: 0xB8F0FF, hex2: 0x4AA8E0, price: 250),
        TimerTheme(id: "mint", name: "Mint", hex1: 0x5EEAD4, hex2: 0x10B981, price: 300),
        TimerTheme(id: "lime", name: "Lime", hex1: 0xD9F99D, hex2: 0x4CB82E, price: 300),
        TimerTheme(id: "grape", name: "Grape", hex1: 0xD08CFF, hex2: 0x7C3AED, price: 300),
        TimerTheme(id: "aurora", name: "Aurora", hex1: 0x6EE7B7, hex2: 0x8B5CF6, price: 400),
        TimerTheme(id: "lava", name: "Lava", hex1: 0xFFD166, hex2: 0xD62828, price: 400),
        TimerTheme(id: "copper", name: "Copper", hex1: 0xF4B183, hex2: 0x9C4A1A, price: 400),
        TimerTheme(id: "midnight", name: "Midnight", hex1: 0x7F8CFF, hex2: 0x1E2A78, price: 500),
        TimerTheme(id: "graphite", name: "Graphite", hex1: 0xE5E5EA, hex2: 0x6E6E78, price: 500)
    ]

    static func find(_ id: String) -> TimerTheme { all.first { $0.id == id } ?? all[0] }
}

/// What the widgets show. The app rewrites it after every change.
struct WidgetSnapshot: Codable {
    struct QuestItem: Codable, Hashable {
        var title: String
        var icon: String
        var progress: Int
        var target: Int
    }

    var updated: Date
    var name: String
    var streak: Int
    var doneToday: Bool
    var score: Int
    var scoreTasks: Int
    var scoreFocus: Int
    var scoreHabits: Int
    var xpToday: Int
    var dailyGoal: Int
    var level: Int
    var levelProgress: Double
    var levelTitle: String
    var focusMinutesToday: Int
    var sessionsToday: Int
    var nextTaskID: String?
    var nextTask: String?
    var nextStep: String?
    var nextStart: Date?
    var openTasks: Int
    var habitsDone: Int
    var habitsTotal: Int
    var quests: [QuestItem]
    var week: [Int]
    var weekDone: [Bool]
    var todayIndex: Int
    var theme: String
    var freezes: Int

    /// Rows for the tappable widgets. Optional so snapshots from older versions still decode.
    struct HabitItem: Codable, Hashable {
        var id: String
        var title: String
        var done: Bool
        var streak: Int
    }
    struct TaskItem: Codable, Hashable {
        var id: String
        var title: String
        var step: String?
        var start: Date?
    }
    var habitItems: [HabitItem]? = nil
    var taskItems: [TaskItem]? = nil
    /// The running focus round, for the StandBy timer widget.
    var focusStart: Date? = nil
    var focusEnd: Date? = nil
    var focusTitle: String? = nil
    /// The running session is a stopwatch, so widgets count up from `focusStart`.
    var focusCountsUp: Bool? = nil

    static let placeholder = WidgetSnapshot(
        updated: Date(), name: "You", streak: 12, doneToday: true, score: 64, scoreTasks: 28, scoreFocus: 22, scoreHabits: 14,
        xpToday: 48, dailyGoal: 20, level: 7, levelProgress: 0.62, levelTitle: "Grinder", focusMinutesToday: 45, sessionsToday: 2,
        nextTaskID: nil, nextTask: "History essay", nextStep: "Open the doc and write one sentence", nextStart: nil, openTasks: 4,
        habitsDone: 2, habitsTotal: 3,
        quests: [QuestItem(title: "Finish 2 focus sessions", icon: "timer", progress: 2, target: 2),
                 QuestItem(title: "Focus for 45 minutes", icon: "hourglass", progress: 45, target: 45),
                 QuestItem(title: "Finish a task", icon: "checkmark.seal.fill", progress: 0, target: 1)],
        week: [52, 71, 40, 88, 64, -1, -1], weekDone: [true, true, true, true, true, false, false], todayIndex: 4, theme: "ember", freezes: 1,
        habitItems: [HabitItem(id: "a", title: "Drink water", done: true, streak: 6),
                     HabitItem(id: "b", title: "Read 10 pages", done: false, streak: 3),
                     HabitItem(id: "c", title: "In bed by 11", done: false, streak: 0)],
        taskItems: [TaskItem(id: "x", title: "History essay", step: "Write one rough sentence", start: nil),
                    TaskItem(id: "y", title: "Bio flashcards", step: "Review one page", start: nil),
                    TaskItem(id: "z", title: "Clean room", step: "Put away five things", start: nil)])

    /// The same data seen from a later day: today's numbers start over, and a streak with no session survives only on freezes.
    func normalized(at now: Date = Date()) -> WidgetSnapshot {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: updated), to: cal.startOfDay(for: now)).day ?? 0
        guard days > 0 else { return self }
        var s = self
        let missed = doneToday ? days - 1 : days
        if missed > freezes { s.streak = 0 }
        s.doneToday = false
        s.score = 0; s.scoreTasks = 0; s.scoreFocus = 0; s.scoreHabits = 0
        s.xpToday = 0; s.focusMinutesToday = 0; s.sessionsToday = 0; s.habitsDone = 0
        s.quests = quests.map { QuestItem(title: $0.title, icon: $0.icon, progress: 0, target: $0.target) }
        s.habitItems = habitItems?.map { h in
            var h = h
            // A habit streak survives into the next day only if it was done on the last day we saw.
            if !(days == 1 && h.done) { h.streak = 0 }
            h.done = false
            return h
        }
        let idx = todayIndex + days
        if idx <= 6 {
            s.todayIndex = idx
            for i in (todayIndex + 1)...idx { s.week[i] = 0; s.weekDone[i] = false }
        } else {
            s.todayIndex = (cal.component(.weekday, from: now) + 5) % 7
            s.week = (0..<7).map { $0 <= s.todayIndex ? 0 : -1 }
            s.weekDone = Array(repeating: false, count: 7)
        }
        s.updated = now
        return s
    }

    static func load() -> WidgetSnapshot? {
        guard let d = UserDefaults(suiteName: SharedConfig.appGroup)?.data(forKey: SharedConfig.snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: d)
    }

    func save() {
        guard let d = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: SharedConfig.appGroup)?.set(d, forKey: SharedConfig.snapshotKey)
    }
}
