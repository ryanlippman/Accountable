import Foundation
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)

/// Starts, updates and ends the focus Live Activity (Lock Screen + Dynamic Island).
enum FocusLive {
    private static var current: Activity<FocusActivityAttributes>?

    static func start(title: String, minutes: Int, theme: TimerTheme, state: FocusActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endAll()
        let attrs = FocusActivityAttributes(taskTitle: title, minutes: minutes, hex1: theme.hex1, hex2: theme.hex2)
        current = try? Activity.request(attributes: attrs,
                                        content: ActivityContent(state: state, staleDate: state.end.addingTimeInterval(30 * 60)),
                                        pushType: nil)
    }

    static func update(_ state: FocusActivityAttributes.ContentState) {
        guard let a = current else { return }
        Task { await a.update(ActivityContent(state: state, staleDate: state.end.addingTimeInterval(30 * 60))) }
    }

    /// Shows "Done" for a few seconds, then leaves.
    static func finish(_ state: FocusActivityAttributes.ContentState) {
        guard let a = current else { return }
        current = nil
        Task { await a.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(8))) }
    }

    static func endAll() {
        current = nil
        for a in Activity<FocusActivityAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
#else
/// The Mac has no Lock Screen or Dynamic Island, so these do nothing.
enum FocusLive {
    static func start(title: String, minutes: Int, theme: TimerTheme, state: FocusActivityAttributes.ContentState) {}
    static func update(_ state: FocusActivityAttributes.ContentState) {}
    static func finish(_ state: FocusActivityAttributes.ContentState) {}
    static func endAll() {}
}
#endif
