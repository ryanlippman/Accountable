import Foundation
import WidgetKit

// How widgets, controls, Siri and Shortcuts talk to the app. Anything that runs outside the app writes
// to the shared App Group; the app applies it the next time it's active (or right away if it's running).

enum WidgetAction: Codable, Equatable {
    case setHabit(id: String, done: Bool)
    case finishTask(id: String)
    case addTask(title: String)
}

enum ActionQueue {
    private static let key = "pendingActions.v1"
    static let darwinName = "com.ryanlippman.accountable.actions"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: SharedConfig.appGroup) }

    static func push(_ action: WidgetAction) {
        guard let d = defaults else { return }
        var list = (d.data(forKey: key)).flatMap { try? JSONDecoder().decode([WidgetAction].self, from: $0) } ?? []
        list.append(action)
        if list.count > 200 { list.removeFirst(list.count - 200) }
        d.set(try? JSONEncoder().encode(list), forKey: key)
        ping()
    }

    static func drain() -> [WidgetAction] {
        guard let d = defaults, let raw = d.data(forKey: key),
              let list = try? JSONDecoder().decode([WidgetAction].self, from: raw) else { return [] }
        d.removeObject(forKey: key)
        return list
    }

    /// Wakes a running copy of the app so it applies the action immediately.
    static func ping() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(darwinName as CFString), nil, nil, true)
    }
}

extension Notification.Name {
    static let accountableRoute = Notification.Name("accountable.route")
    static let accountableActions = Notification.Name("accountable.actions")
}

/// Screens to open, requested by intents that launch the app.
enum AppRoute {
    private static let key = "pendingRoute.v1"

    static func focus(minutes: Int?, taskID: String?) -> URL {
        var c = URLComponents()
        c.scheme = SharedConfig.scheme
        c.host = "focus"
        var q: [URLQueryItem] = []
        if let minutes { q.append(URLQueryItem(name: "minutes", value: "\(minutes)")) }
        if let taskID { q.append(URLQueryItem(name: "task", value: taskID)) }
        c.queryItems = q.isEmpty ? nil : q
        return c.url ?? URL(string: "\(SharedConfig.scheme)://focus")!
    }

    static let dump = URL(string: "\(SharedConfig.scheme)://dump")!
    static let today = URL(string: "\(SharedConfig.scheme)://today")!
    static let progress = URL(string: "\(SharedConfig.scheme)://progress")!

    static func post(_ url: URL) {
        UserDefaults(suiteName: SharedConfig.appGroup)?.set(url.absoluteString, forKey: key)
        UserDefaults.standard.set(url.absoluteString, forKey: key)
        NotificationCenter.default.post(name: .accountableRoute, object: url)
    }

    /// The route waiting to be opened, if any. Reading it clears it.
    static func take() -> URL? {
        for d in [UserDefaults(suiteName: SharedConfig.appGroup), UserDefaults.standard].compactMap({ $0 }) {
            if let s = d.string(forKey: key) {
                d.removeObject(forKey: key)
                return URL(string: s)
            }
        }
        return nil
    }
}
