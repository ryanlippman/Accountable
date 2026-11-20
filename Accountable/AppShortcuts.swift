import AppIntents

/// Adds a task by voice or from a Shortcut, without opening the app.
struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a task"
    static let description = IntentDescription("Adds a task to Accountable with a tiny first step.")

    @Parameter(title: "Task", requestValueDialog: "What do you need to do?") var task: String

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let t = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return .result(dialog: "Nothing to add.") }
        ActionQueue.push(.addTask(title: t))
        return .result(dialog: "Added \u{201C}\(t)\u{201D}.")
    }
}

/// Phrases Siri understands out of the box. These also show up in Shortcuts, Spotlight and the Action button.
struct AccountableShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartFocusIntent(),
                    phrases: ["Start a focus session in \(.applicationName)",
                              "Focus with \(.applicationName)",
                              "Start \(.applicationName)",
                              "Lock in with \(.applicationName)"],
                    shortTitle: "Start focus",
                    systemImageName: "timer")
        AppShortcut(intent: BrainDumpIntent(),
                    phrases: ["Brain dump in \(.applicationName)",
                              "Empty my head with \(.applicationName)",
                              "Start a brain dump in \(.applicationName)"],
                    shortTitle: "Brain dump",
                    systemImageName: "mic.fill")
        AppShortcut(intent: AddTaskIntent(),
                    phrases: ["Add a task to \(.applicationName)",
                              "Add to \(.applicationName)"],
                    shortTitle: "Add task",
                    systemImageName: "plus.circle.fill")
    }
}
