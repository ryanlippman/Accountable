import AppIntents
import WidgetKit

// App Intents compiled into both the app and the widget extension, so the same actions power
// tappable widgets, Control Center, Siri, Shortcuts and the Action button.

/// Checks a habit on or off right from a widget, without opening the app.
struct SetHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Check off a habit"
    static let isDiscoverable = false

    @Parameter(title: "Habit") var habitID: String
    @Parameter(title: "Done") var done: Bool

    init() {}
    init(habitID: String, done: Bool) {
        self.habitID = habitID
        self.done = done
    }

    func perform() async throws -> some IntentResult {
        ActionQueue.push(.setHabit(id: habitID, done: done))
        if var s = WidgetSnapshot.load(), var items = s.habitItems, let i = items.firstIndex(where: { $0.id == habitID }) {
            if items[i].done != done {
                items[i].done = done
                items[i].streak = max(0, items[i].streak + (done ? 1 : -1))
                s.habitItems = items
                s.habitsDone = items.filter(\.done).count
                s.save()
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Finishes a task from a widget. The loot drop is waiting when you next open the app.
struct FinishTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Finish a task"
    static let isDiscoverable = false

    @Parameter(title: "Task") var taskID: String

    init() {}
    init(taskID: String) { self.taskID = taskID }

    func perform() async throws -> some IntentResult {
        ActionQueue.push(.finishTask(id: taskID))
        if var s = WidgetSnapshot.load(), var items = s.taskItems {
            items.removeAll { $0.id == taskID }
            s.taskItems = items
            s.openTasks = max(0, s.openTasks - 1)
            if s.nextTaskID == taskID {
                s.nextTaskID = items.first?.id
                s.nextTask = items.first?.title
                s.nextStep = items.first?.step
                s.nextStart = items.first?.start
            }
            s.save()
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Opens the app straight into a focus session.
struct StartFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a focus session"
    static let description = IntentDescription("Opens Accountable and starts a focus session.")
    static let openAppWhenRun = true

    @Parameter(title: "Minutes", default: 5) var minutes: Int
    @Parameter(title: "Task ID") var taskID: String?

    init() {}
    init(minutes: Int, taskID: String? = nil) {
        self.minutes = minutes
        self.taskID = taskID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // 0 means "use my default length".
        AppRoute.post(AppRoute.focus(minutes: minutes > 0 ? min(180, minutes) : nil, taskID: taskID))
        return .result()
    }
}

/// Opens the app straight into a voice brain dump.
struct BrainDumpIntent: AppIntent {
    static let title: LocalizedStringResource = "Brain dump"
    static let description = IntentDescription("Opens Accountable and starts listening. Say everything on your mind and it becomes tasks.")
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRoute.post(AppRoute.dump)
        return .result()
    }
}
