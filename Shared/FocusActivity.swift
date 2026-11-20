import Foundation
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

/// The focus timer on the Lock Screen and in the Dynamic Island (iPhone only).
/// On the Mac the same types exist so the rest of the app compiles, but nothing is shown.
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "starter", "focus" or "done"
        var phase: String
        var start: Date
        var end: Date
        var combo: Int
        var faceDown: Bool
        var xp: Int
        /// Counting up instead of down. `start` is when focus began; `end` is the safety cap.
        var stopwatch: Bool = false
        /// Start of the current five-minute combo window, so the ring can fill toward the next combo.
        var lap: Date = .distantPast
    }

    var taskTitle: String
    var minutes: Int
    var hex1: UInt32
    var hex2: UInt32
}
#else
struct FocusActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String
        var start: Date
        var end: Date
        var combo: Int
        var faceDown: Bool
        var xp: Int
        /// Counting up instead of down. `start` is when focus began; `end` is the safety cap.
        var stopwatch: Bool = false
        /// Start of the current five-minute combo window, so the ring can fill toward the next combo.
        var lap: Date = .distantPast
    }

    var taskTitle: String
    var minutes: Int
    var hex1: UInt32
    var hex2: UInt32
}
#endif
