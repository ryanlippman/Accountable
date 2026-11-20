import Foundation
import SwiftUI

// MARK: - Day keys and seeded randomness

enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(_ d: Date) -> String { formatter.string(from: d) }
    static func date(_ k: String) -> Date? { formatter.date(from: k) }
    static func add(_ k: String, _ n: Int) -> String {
        let d = date(k) ?? Date()
        return string(Calendar.current.date(byAdding: .day, value: n, to: d) ?? d)
    }
    static var today: String { string(Date()) }
}

extension Date {
    var dayKey: String { DayKey.string(self) }
}

func stableHash(_ s: String) -> UInt64 {
    var h: UInt64 = 1_469_598_103_934_665_603
    for b in s.utf8 {
        h ^= UInt64(b)
        h = h &* 1_099_511_628_211
    }
    return h
}

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Loot

enum Rarity: Int, Codable, CaseIterable {
    case common = 0, rare, epic, legendary

    var name: String { ["Common", "Rare", "Epic", "Legendary"][rawValue] }
    var color: Color { [Color(hex: 0x9AA3B5), Color(hex: 0x3E8BFF), Color(hex: 0xA855F7), Color(hex: 0xF5B021)][rawValue] }
    var bonusXP: Int { [0, 15, 40, 100][rawValue] }
    var sparks: Int { [5, 15, 40, 120][rawValue] }
    var odds: String { ["60%", "25%", "12%", "3%"][rawValue] }

    static func roll() -> Rarity {
        let r = Int.random(in: 0..<1000)
        if r < 30 { return .legendary }
        if r < 150 { return .epic }
        if r < 400 { return .rare }
        return .common
    }
}

// MARK: - Stored data

/// One small piece of a bigger task.
struct Subtask: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var done = false
}

struct WorkTask: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var created = Date()
    var done: Date? = nil
    var focusMinutes = 0
    var sessions = 0
    var plannedStart: Date? = nil
    var planResult: String? = nil   // "onTime", "late", "missed"
    var rarity: Rarity? = nil
    var firstStep: String? = nil
    var updated = Date()
    /// Small steps from "Break it down".
    var steps: [Subtask] = []
    /// When it's due, e.g. read off an assignment sheet.
    var due: Date? = nil

    /// The next thing to actually do: the first unfinished step, else the tiny first step.
    var nextAction: String? { steps.first(where: { !$0.done })?.title ?? firstStep }

    init(title: String, firstStep: String? = nil) {
        self.title = title
        self.firstStep = firstStep
    }

    enum CodingKeys: String, CodingKey {
        case id, title, created, done, focusMinutes, sessions, plannedStart, planResult, rarity, firstStep, updated, steps, due
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        done = try c.decodeIfPresent(Date.self, forKey: .done)
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 0
        sessions = try c.decodeIfPresent(Int.self, forKey: .sessions) ?? 0
        plannedStart = try c.decodeIfPresent(Date.self, forKey: .plannedStart)
        planResult = try c.decodeIfPresent(String.self, forKey: .planResult)
        rarity = try c.decodeIfPresent(Rarity.self, forKey: .rarity)
        firstStep = try c.decodeIfPresent(String.self, forKey: .firstStep)
        updated = try c.decodeIfPresent(Date.self, forKey: .updated) ?? done ?? created
        steps = try c.decodeIfPresent([Subtask].self, forKey: .steps) ?? []
        due = try c.decodeIfPresent(Date.self, forKey: .due)
    }
}

struct Habit: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    init(title: String) { self.title = title }
}

struct DayLog: Codable {
    var xp = 0
    var sessions = 0
    var focusMinutes = 0
    var habits: [UUID] = []
    var tasksDone = 0
    var focusedTasksDone = 0
    var maxCombo = 0
    var earlyStart = false
    var phoneDown = 0
    var frozen = false
    var claimed: [String] = []
    var chest = false
    var pledge = ""
    var pledgeDone = false
    var plans = 0
    var onTime = 0
    var firstSteps = 0
    var comeback = false

    init() {}

    enum CodingKeys: String, CodingKey {
        case xp, sessions, focusMinutes, habits, tasksDone, focusedTasksDone, maxCombo, earlyStart, phoneDown, frozen, claimed, chest, pledge, pledgeDone, plans, onTime, firstSteps, comeback
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        xp = try c.decodeIfPresent(Int.self, forKey: .xp) ?? 0
        sessions = try c.decodeIfPresent(Int.self, forKey: .sessions) ?? 0
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 0
        habits = try c.decodeIfPresent([UUID].self, forKey: .habits) ?? []
        tasksDone = try c.decodeIfPresent(Int.self, forKey: .tasksDone) ?? 0
        focusedTasksDone = try c.decodeIfPresent(Int.self, forKey: .focusedTasksDone) ?? 0
        maxCombo = try c.decodeIfPresent(Int.self, forKey: .maxCombo) ?? 0
        earlyStart = try c.decodeIfPresent(Bool.self, forKey: .earlyStart) ?? false
        phoneDown = try c.decodeIfPresent(Int.self, forKey: .phoneDown) ?? 0
        frozen = try c.decodeIfPresent(Bool.self, forKey: .frozen) ?? false
        claimed = try c.decodeIfPresent([String].self, forKey: .claimed) ?? []
        chest = try c.decodeIfPresent(Bool.self, forKey: .chest) ?? false
        pledge = try c.decodeIfPresent(String.self, forKey: .pledge) ?? ""
        pledgeDone = try c.decodeIfPresent(Bool.self, forKey: .pledgeDone) ?? false
        plans = try c.decodeIfPresent(Int.self, forKey: .plans) ?? 0
        onTime = try c.decodeIfPresent(Int.self, forKey: .onTime) ?? 0
        firstSteps = try c.decodeIfPresent(Int.self, forKey: .firstSteps) ?? 0
        comeback = try c.decodeIfPresent(Bool.self, forKey: .comeback) ?? false
    }
}

struct SessionRecord: Codable, Identifiable {
    var id = UUID()
    var start: Date
    var minutes: Int
    var xp: Int
    var taskID: UUID?
    var distractions: Int
    var phoneDown: Double
}

struct RepairOffer: Codable {
    var gap: [String]
    var expires: String
    var streak: Int
}

/// What onboarding learned. Every answer changes something the person sees.
struct Personal: Codable {
    var obstacles: [String] = []
    var outcome = ""
    var reminderSlot = "evening"
    var planHelp = true

    var launchpad: Bool { obstacles.contains("start") || obstacles.contains("prioritize") || obstacles.isEmpty }
    var wantsShort: Bool { obstacles.contains("start") || obstacles.contains("focus") }
}

struct AppData: Codable {
    var name = "Ryan"
    var onboarded = false
    var created = Date()
    var tasks: [WorkTask] = []
    var habits: [Habit] = []
    var days: [String: DayLog] = [:]
    var sessions: [SessionRecord] = []
    var totalXP = 0
    var sparks = 300
    var shields = 5
    var shieldsDay = ""
    var freezes = 1
    var bestStreak = 0
    var repair: RepairOffer? = nil
    var lostStreakSeen = ""
    var dailyGoal = 20
    var defaultMinutes = 20
    var reminderHour = 19
    var reminderMinute = 30
    var prework: [String] = ["Phone on Do Not Disturb", "Water on the desk", "Every other tab closed"]
    var strict = true
    var theme = "ember"
    var owned: [String] = ["ember"]
    var boostUntil: Date? = nil
    var achievementsSeen: [String: Int] = [:]
    var questsByMonth: [String: Int] = [:]
    var personal = Personal()
    var stats: [String: Int] = [:]
    var lastActiveDay = ""
    var activeDays = 0

    /// Soundscape layer volumes (0...1) by layer id, and whether they play during focus.
    var soundLevels: [String: Double] = ["rain": 0.6]
    var soundOn = false
    /// Master volume for the whole soundscape.
    var soundMaster: Double = 0.8
    /// The Focus tab remembers whether you last used the timer or the stopwatch.
    var focusStopwatch = false
}

// MARK: - Session plumbing

struct SessionConfig: Identifiable, Equatable {
    let id = UUID()
    var taskID: UUID?
    var minutes: Int
    var recovery = false
    /// Skips the pre-work checklist (first win, rescue, quick starts).
    var quick = false
    /// Open-ended: the clock counts up and you finish whenever you're ready.
    var stopwatch = false
}

struct SessionResult {
    var config: SessionConfig
    var started: Date
    var focusedMinutes: Int
    var maxCombo: Int
    var distractions: Int
    var phoneDownRatio: Double
    var onTime: Bool
}

struct SessionReward {
    var total: Int
    var lines: [(String, Int)]
    var halved: Bool
    var boosted: Bool
    var focusedMinutes: Int
    var maxCombo: Int
    var phoneDownRatio: Double
    var distractions: Int
    var streakBefore: Int
    var streakAfter: Int
    var firstToday: Bool
    var shieldRestored: Bool
    var comeback: Bool
}

// MARK: - Quests and achievements

struct Quest: Identifiable {
    let id: String
    let title: String
    let icon: String
    let target: Int
    let progress: Int
    let sparks: Int
    var done: Bool { progress >= target }
    var fraction: Double { Double(min(progress, target)) / Double(max(target, 1)) }
}

struct Achievement: Identifiable {
    let id: String
    let title: String
    let icon: String
    let color: Color
    let tiers: [Int]
    let unit: String
    let metric: (AppStore) -> Int
}

/// The day's focus score, 0 to 100, weighted like the web version: tasks 45, focus time 30, habits 25.
struct DayScore {
    var total: Int
    var tasks: Int
    var focus: Int
    var habits: Int
    var tasksFraction: Double
    var focusFraction: Double
    var habitsFraction: Double
}

// MARK: - Popups

enum PopupKind {
    case levelUp(Int)
    case loot(title: String, rarity: Rarity, xp: Int, sparks: Int)
    case quest(title: String, sparks: Int)
    case allQuests
    case achievement(title: String, icon: String, tier: Int, detail: String)
    case streakMilestone(Int)
    case welcomeBack(daysAway: Int, lostStreak: Int)
    case freezeUsed(Int)
    case dailyGoal(Int)
    case shieldLost(String)
    case pledgeDone
    case personalBest(String)

    /// Small kinds show as a banner at the top and dismiss on their own.
    var isBanner: Bool {
        switch self {
        case .quest, .shieldLost, .freezeUsed, .dailyGoal, .pledgeDone, .personalBest: return true
        default: return false
        }
    }
}

/// What it takes to take back a just-finished task.
struct UndoInfo {
    var taskID: UUID
    var xp: Int
    var sparks: Int
    var focused: Bool
}

struct Popup: Identifiable {
    let id = UUID()
    let kind: PopupKind
}
