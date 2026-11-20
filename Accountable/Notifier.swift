import Foundation
import UserNotifications

/// All local notifications: daily streak reminders, "streak at risk" nudges, planned task starts and session ends.
enum Notifier {
    static var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    static func requestAuthorization(_ done: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
            DispatchQueue.main.async { done(ok) }
        }
    }

    private static func request(_ id: String, _ title: String, _ body: String, at date: Date) -> UNNotificationRequest? {
        guard date > Date().addingTimeInterval(3) else { return nil }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
    }

    private static let daily = [
        "Your next step is one tap away. Start the 2-minute starter.",
        "A short session today keeps things moving.",
        "Pick one small thing. Accountable will time it.",
        "Your quests reset at midnight. There are sparks waiting.",
        "Phone face down, timer on. You've got this."
    ]
    private static let comeback = [
        "Welcome back whenever you're ready. Your next step is waiting.",
        "No pressure. Even a 5-minute session counts.",
        "Life got busy? Start small: one 2-minute starter.",
        "Your progress is all still here. Pick up where you left off."
    ]

    /// Rebuilds every streak and task reminder from the current data.
    static func reschedule(_ store: AppStore) {
        let d = store.data
        guard d.onboarded else { return }
        let streak = store.streak
        let doneToday = store.doneToday
        let cal = Calendar.current
        let now = Date()
        var reqs: [UNNotificationRequest] = []

        for offset in 0..<10 {
            guard d.personal.reminderSlot != "none",
                  let day = cal.date(byAdding: .day, value: offset, to: now),
                  let at = cal.date(bySettingHour: d.reminderHour, minute: d.reminderMinute, second: 0, of: day) else { continue }
            if offset == 0 && doneToday { continue }
            let body: String
            if offset >= 2 {
                body = comeback[(offset - 2) % comeback.count]
            } else if streak > 0 {
                body = offset == 0 ? "Your \(streak)-day streak is here when you're ready. Five minutes counts." : daily[(offset + streak) % daily.count]
            } else {
                body = daily[offset % daily.count]
            }
            if let r = request("daily-\(offset)", "Accountable", body, at: at) { reqs.append(r) }

            // Last call before midnight when a streak is on the line.
            if (offset == 0 && !doneToday && streak > 0) || (offset == 1 && (streak > 0 || doneToday)) {
                let n = offset == 0 ? streak : max(streak, 1)
                if let late = cal.date(bySettingHour: 21, minute: 45, second: 0, of: day),
                   let r = request("risk-\(offset)", "Still time for today",
                                   "One short session keeps it going. A 5-minute one counts.", at: late) {
                    reqs.append(r)
                }
            }
        }

        for t in d.tasks where t.done == nil && t.planResult == nil {
            guard let at = t.plannedStart else { continue }
            if let r = request("task-\(t.id.uuidString)", "Time to start: \(t.title)", "Start within 15 minutes for the on-time bonus.", at: at) { reqs.append(r) }
            if let r = request("taskmiss-\(t.id.uuidString)", "\(t.title) hasn't started", "Starting in the next 5 minutes keeps your shield safe.", at: at.addingTimeInterval(10 * 60)) { reqs.append(r) }
        }

        let ids = reqs.map { $0.identifier }
        center.getPendingNotificationRequests { pending in
            let stale = pending.map { $0.identifier }.filter { id in
                (id.hasPrefix("daily-") || id.hasPrefix("risk-") || id.hasPrefix("task")) && !ids.contains(id)
            }
            center.removePendingNotificationRequests(withIdentifiers: stale + ids)
            for r in reqs { center.add(r) }
        }
    }

    static func cancelTask(_ id: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: ["task-\(id.uuidString)", "taskmiss-\(id.uuidString)"])
    }

    static func scheduleSessionEnd(at date: Date) {
        center.removePendingNotificationRequests(withIdentifiers: ["session-end"])
        if let r = request("session-end", "Session complete!", "Come back and claim your XP.", at: date) { center.add(r) }
    }

    static func cancelSessionEnd() {
        center.removePendingNotificationRequests(withIdentifiers: ["session-end"])
    }

    static func removeAll() {
        center.removeAllPendingNotificationRequests()
    }
}

/// Shows notifications as banners even while the app is open.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.identifier == "session-end" {
            completionHandler([])
        } else {
            completionHandler([.banner, .sound])
        }
    }
}
