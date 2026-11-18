import AppKit
import CoreAudio

/// Watches idle time, the frontmost app, and whether Spotify or Music is
/// actually playing. The walk animation does not run here; this ticks slowly.
@MainActor
final class DeskWatch: NSObject {
    var onSample: ((DeskSample) -> Void)?
    private(set) var latest = DeskSample(
        idleSeconds: 0,
        frontmostBundleID: nil,
        musicPlaying: false,
        coffeeBreak: false,
        reminderDue: false
    )

    private var clock = DeskClock()
    private var timer: Timer?
    private var lastTick = Date()
    private var musicPlaying = false
    private var notifiedPlaying: Bool?

    func start() {
        guard timer == nil else { return }
        listenForMusic()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        lastTick = Date()
        publish(advanceClock: true)
        let timer = Timer(timeInterval: 2, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func tick() {
        publish(advanceClock: true)
    }

    @objc private func frontmostChanged() {
        guard Thread.isMainThread else {
            perform(#selector(frontmostChanged), on: Thread.main, with: nil, waitUntilDone: false)
            return
        }
        publish(advanceClock: false)
    }

    @objc private func musicNote(_ note: Notification) {
        guard Thread.isMainThread else {
            perform(#selector(musicNote(_:)), on: Thread.main, with: note, waitUntilDone: false)
            return
        }
        guard let state = note.userInfo?["Player State"] as? String else { return }
        notifiedPlaying = state == "Playing"
        publish(advanceClock: false)
    }

    private func publish(advanceClock: Bool) {
        let idle = Self.idleSeconds()
        if advanceClock {
            let now = Date()
            // A lid-open can land many minutes later. Only the gap we actually
            // watched counts, so waking the Mac does not instantly brew coffee.
            let delta = min(5, max(0, now.timeIntervalSince(lastTick)))
            lastTick = now
            clock.advance(by: delta, idleSeconds: idle)
        }
        refreshMusic(trustNotification: !advanceClock)
        latest = DeskSample(
            idleSeconds: idle,
            frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            musicPlaying: musicPlaying,
            coffeeBreak: clock.onBreak,
            reminderDue: false,
            workSeconds: clock.workSeconds,
            coffeeRemaining: clock.coffeeRemaining
        )
        onSample?(latest)
    }

    /// CoreAudio is the source of truth on the slow tick, so a missed pause
    /// notification cannot leave the cat bobbing. A fresh notification may
    /// turn the bob on immediately, and the next tick confirms it.
    private func refreshMusic(trustNotification: Bool) {
        if let audible = Self.musicAppIsAudible() {
            if trustNotification {
                musicPlaying = audible || notifiedPlaying == true
            } else {
                musicPlaying = audible
            }
        } else if let notifiedPlaying {
            musicPlaying = notifiedPlaying
        }
    }

    private func listenForMusic() {
        let center = DistributedNotificationCenter.default()
        let names = [
            "com.spotify.client.PlaybackStateChanged",
            "com.apple.iTunes.playerInfo",
            "com.apple.Music.playerInfo",
        ]
        for name in names {
            center.addObserver(
                self,
                selector: #selector(musicNote(_:)),
                name: Notification.Name(name),
                object: nil,
                suspensionBehavior: .deliverImmediately
            )
        }
    }

    static func idleSeconds() -> TimeInterval {
        let types: [CGEventType] = [
            .keyDown,
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .scrollWheel,
        ]
        var quietest = TimeInterval.greatestFiniteMagnitude
        for type in types {
            let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
            if seconds >= 0 {
                quietest = min(quietest, seconds)
            }
        }
        if quietest == .greatestFiniteMagnitude { return 0 }
        return quietest
    }

    /// Nil when the audio process list cannot be read. False when Spotify and
    /// Music are quiet or not running. Browser audio is ignored on purpose.
    static func musicAppIsAudible() -> Bool? {
        let players: Set<String> = ["com.spotify.client", "com.apple.Music"]
        let apps = NSWorkspace.shared.runningApplications.filter { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return players.contains(bundleID)
        }
        if apps.isEmpty { return false }
        var sawAnswer = false
        for app in apps {
            switch isOutputRunning(pid: app.processIdentifier) {
            case .some(true):
                return true
            case .some(false):
                sawAnswer = true
            case .none:
                break
            }
        }
        return sawAnswer ? false : nil
    }

    private static func isOutputRunning(pid: pid_t) -> Bool? {
        var pid = pid
        var translate = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var objectID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &translate,
            UInt32(MemoryLayout<pid_t>.size),
            &pid,
            &size,
            &objectID
        )
        if status != noErr { return nil }
        if objectID == kAudioObjectUnknown { return false }
        var running = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var flag: UInt32 = 0
        var flagSize = UInt32(MemoryLayout<UInt32>.size)
        let runStatus = AudioObjectGetPropertyData(objectID, &running, 0, nil, &flagSize, &flag)
        if runStatus != noErr { return nil }
        return flag != 0
    }
}
