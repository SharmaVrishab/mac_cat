import Foundation

/// What the desk is doing right now. Movement code turns this into a pose.
/// The cat still picks its own destination; a cue never points at the cursor.
enum DeskCue: Equatable {
    case reminder
    case idleSleep
    case coffee
    case roam(coding: Bool, vibe: Bool)
}

struct DeskSample: Equatable {
    var idleSeconds: TimeInterval
    var frontmostBundleID: String?
    var musicPlaying: Bool
    var coffeeBreak: Bool
    var reminderDue: Bool
    var workSeconds: TimeInterval = 0
    var coffeeRemaining: TimeInterval = 0
}

struct DeskStatusLine: Equatable {
    var title: String
    var detail: String
}

enum DeskPolicy {
    /// Curl up once the keyboard and mouse have been quiet this long.
    static let idleSleepAfter: TimeInterval = 90
    /// A real absence. Shorter gaps still count as the work session.
    static let pauseWorkAfterIdle: TimeInterval = 5 * 60
    static let coffeeAfter: TimeInterval = 45 * 60
    static let coffeeBreak: TimeInterval = 3 * 60

    static func cue(_ sample: DeskSample) -> DeskCue {
        if sample.reminderDue { return .reminder }
        if sample.idleSeconds >= idleSleepAfter { return .idleSleep }
        if sample.coffeeBreak { return .coffee }
        return .roam(coding: isCodingApp(sample.frontmostBundleID), vibe: sample.musicPlaying)
    }

    static func isCodingApp(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        if bundleID == "com.apple.dt.Xcode"
            || bundleID == "com.microsoft.VSCode"
            || bundleID == "com.microsoft.VSCodeInsiders"
            || bundleID == "com.apple.Terminal"
            || bundleID == "com.googlecode.iterm2"
            || bundleID == "dev.warp.Warp-Stable" {
            return true
        }
        if bundleID.hasPrefix("com.todesktop.") { return true }
        if bundleID.hasPrefix("com.jetbrains.") { return true }
        if bundleID.hasPrefix("dev.warp.") { return true }
        return false
    }

    /// One title and one sentence for the care panel. The clock is either
    /// minutes toward coffee, or time left in the break.
    static func line(cue: DeskCue, workSeconds: TimeInterval, coffeeRemaining: TimeInterval) -> DeskStatusLine {
        switch cue {
        case .reminder:
            return DeskStatusLine(
                title: "Reminder",
                detail: "Sitting up until you snooze or finish it."
            )
        case .idleSleep:
            return DeskStatusLine(
                title: "Napping",
                detail: "Asleep after 90 seconds away from the keyboard."
            )
        case .coffee:
            return DeskStatusLine(
                title: "Coffee break",
                detail: "Mug for 3 minutes. \(breakLeft(coffeeRemaining))."
            )
        case .roam(let coding, let vibe):
            let focus = "\(focusMinutes(workSeconds)) of 45 min toward coffee"
            if coding, vibe {
                return DeskStatusLine(
                    title: "Coding with you",
                    detail: "Listening along. \(focus)."
                )
            }
            if coding {
                return DeskStatusLine(
                    title: "Coding with you",
                    detail: "Staying by the editor. \(focus)."
                )
            }
            if vibe {
                return DeskStatusLine(
                    title: "Listening",
                    detail: "Bobbing to Spotify or Music. \(focus)."
                )
            }
            return DeskStatusLine(
                title: "Wandering",
                detail: "Moving between sits and walks. \(focus)."
            )
        }
    }

    private static func focusMinutes(_ workSeconds: TimeInterval) -> Int {
        min(45, Int(workSeconds / 60))
    }

    private static func breakLeft(_ seconds: TimeInterval) -> String {
        let left = max(0, Int(seconds.rounded(.up)))
        if left >= 60 {
            let minutes = (left + 59) / 60
            return minutes == 1 ? "1 min left" : "\(minutes) min left"
        }
        return "\(left)s left"
    }
}

/// Counts focused time toward a coffee break. Idle of five minutes or more
/// pauses the count and does not throw away the minutes already earned.
struct DeskClock: Equatable {
    var workSeconds: TimeInterval = 0
    var coffeeRemaining: TimeInterval = 0

    var onBreak: Bool { coffeeRemaining > 0 }

    mutating func advance(by delta: TimeInterval, idleSeconds: TimeInterval) {
        guard delta > 0 else { return }
        if coffeeRemaining > 0 {
            coffeeRemaining = max(0, coffeeRemaining - delta)
            if coffeeRemaining == 0 {
                workSeconds = 0
            }
            return
        }
        if idleSeconds >= DeskPolicy.pauseWorkAfterIdle {
            return
        }
        workSeconds += delta
        if workSeconds >= DeskPolicy.coffeeAfter {
            coffeeRemaining = DeskPolicy.coffeeBreak
        }
    }
}
