import AppKit

enum ScreenClamp {
    /// Returns a frame fully inside one of `screens` when `window` is not already
    /// fully inside one. Returns nil when the window is already inside, or when
    /// no screen is connected yet.
    static func clamped(_ window: CGRect, onto screens: [CGRect]) -> CGRect? {
        let available = screens.filter { $0.width > 1 && $0.height > 1 }
        guard !available.isEmpty else { return nil }
        if available.contains(where: { $0.contains(window) }) {
            return nil
        }
        let target = available.max { lhs, rhs in
            lhs.intersection(window).area < rhs.intersection(window).area
        } ?? available[0]
        var frame = window
        if frame.width > target.width { frame.size.width = target.width }
        if frame.height > target.height { frame.size.height = target.height }
        if frame.maxX > target.maxX { frame.origin.x = target.maxX - frame.width }
        if frame.minX < target.minX { frame.origin.x = target.minX }
        if frame.maxY > target.maxY { frame.origin.y = target.maxY - frame.height }
        if frame.minY < target.minY { frame.origin.y = target.minY }
        return frame
    }
}

@MainActor
final class CatBehavior: NSObject {
    let window: NSWindow
    var stage: () -> CatStage = { .kitten }
    var onPose: ((CatPose) -> Void)?
    var onHiddenChange: ((Bool) -> Void)?
    var onPausedChange: ((Bool) -> Void)?

    private(set) var paused = false
    private(set) var hidden = false
    private var action: CatAction = .sit
    private var frame = 0
    private var frameTick = 0
    private var facingLeft = false
    private var blink = false
    private var destination: NSPoint?
    private var happyUntil: Date?
    private var walkTimer: Timer?
    private var poseTimer: Timer?
    private var displayedPose: CatPose?
    private var screenRetries = 0
    private var cue: DeskCue = .roam(coding: false, vibe: false)
    private var holding = false
    private var coding = false
    private var vibe = false
    private let speed: CGFloat = 48

    init(window: NSWindow) {
        self.window = window
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func start(hiddenUntil: Date?) {
        if let hiddenUntil, hiddenUntil > Date() {
            hideUntil(hiddenUntil)
            return
        }
        window.ignoresMouseEvents = false
        window.orderFrontRegardless()
        beginIdle(after: 1.2)
    }

    func pause() {
        guard !paused else { return }
        paused = true
        stopMoving()
        window.ignoresMouseEvents = true
        onPausedChange?(true)
        emit()
    }

    func resume() {
        guard paused else { return }
        paused = false
        onPausedChange?(false)
        guard !hidden else { return }
        window.ignoresMouseEvents = false
        settleFromCue(afterIdle: 0.4)
    }

    func hide(for interval: TimeInterval) {
        hideUntil(Date().addingTimeInterval(interval))
    }

    func show() {
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(unhide),
            object: nil
        )
        hidden = false
        onHiddenChange?(false)
        window.ignoresMouseEvents = paused
        window.orderFrontRegardless()
        clampToScreens()
        if !paused {
            settleFromCue(afterIdle: 0.4)
        }
    }

    /// Smile and confetti in place. Desk cues wait until this ends.
    func playCheer() {
        guard !paused, !hidden else { return }
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(endCheer),
            object: nil
        )
        stopMoving()
        holding = true
        vibe = false
        action = .happy
        blink = false
        frame = 0
        destination = nil
        happyUntil = Date().addingTimeInterval(3.5)
        emit()
        perform(#selector(endCheer), with: nil, afterDelay: 3.5)
    }

    /// Applies a desk cue. Roaming still picks a random spot on the screen.
    func noteDesk(_ sample: DeskSample) {
        let next = DeskPolicy.cue(sample)
        cue = next
        if case .roam(let coding, let vibe) = next {
            self.coding = coding
            self.vibe = vibe
        } else {
            vibe = false
        }
        guard !paused, !hidden else { return }
        if let happyUntil, Date() < happyUntil {
            action = .happy
            vibe = false
            emit()
            return
        }
        applyCue(next)
    }

    func noteStageChanged() {
        emit()
    }

    func userGrabbed() {
        guard !paused, !hidden else { return }
        stopMoving()
    }

    func userReleased() {
        guard !paused, !hidden else { return }
        settleFromCue(afterIdle: Double.random(in: 2...6))
    }

    @objc private func screensChanged() {
        if NSScreen.screens.isEmpty {
            guard screenRetries < 8 else { return }
            screenRetries += 1
            NSObject.cancelPreviousPerformRequests(
                withTarget: self,
                selector: #selector(screensChanged),
                object: nil
            )
            perform(#selector(screensChanged), with: nil, afterDelay: 0.25)
            return
        }
        screenRetries = 0
        clampToScreens()
        if (action == .walk || action == .happy), !destinationIsOnAScreen {
            stopMoving()
            settleFromCue(afterIdle: 0.6)
        }
    }

    @objc private func step() {
        guard !paused, !hidden else {
            stopMoving()
            return
        }
        if let happyUntil, Date() >= happyUntil {
            settleFromCue(afterIdle: Double.random(in: 4...10))
            return
        }
        guard let destination else {
            beginIdle(after: 0.8)
            return
        }
        if !destinationIsOnAScreen {
            stopMoving()
            settleFromCue(afterIdle: 0.6)
            return
        }
        let origin = window.frame.origin
        let dx = destination.x - origin.x
        let dy = destination.y - origin.y
        let distance = hypot(dx, dy)
        let stepSize = speed / 12
        if distance <= stepSize {
            window.setFrameOrigin(destination)
            self.destination = nil
            beginIdle(after: nil)
            return
        }
        if abs(dx) > 1 {
            facingLeft = dx < 0
        }
        let next = NSPoint(
            x: (origin.x + dx / distance * stepSize).rounded(),
            y: (origin.y + dy / distance * stepSize).rounded()
        )
        window.setFrameOrigin(next)
        frameTick += 1
        if frameTick % 6 == 0 {
            frame = (frame + 1) % 4
        }
        emit()
    }

    @objc private func beginWalkFromIdle() {
        guard !paused, !hidden, happyUntil == nil else { return }
        guard case .roam = cue else { return }
        startMoving(.walk)
    }

    @objc private func poseTick() {
        guard !paused, !hidden, walkTimer == nil else {
            updatePoseTimer()
            return
        }
        frame = (frame + 1) % 4
        emit()
    }

    @objc private func endCheer() {
        guard happyUntil != nil else { return }
        settleFromCue(afterIdle: 0.8)
    }

    @objc private func blinkOn() {
        guard action == .sit || action == .work || action == .coffee, !paused, !hidden else { return }
        blink = true
        emit()
        perform(#selector(blinkOff), with: nil, afterDelay: 0.14)
    }

    @objc private func blinkOff() {
        blink = false
        emit()
    }

    @objc private func unhide() {
        show()
    }

    private func hideUntil(_ date: Date) {
        stopMoving()
        hidden = true
        onHiddenChange?(true)
        window.ignoresMouseEvents = true
        window.orderOut(nil)
        let delay = max(0.2, date.timeIntervalSinceNow)
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(unhide),
            object: nil
        )
        perform(#selector(unhide), with: nil, afterDelay: delay)
    }

    private func applyCue(_ next: DeskCue) {
        switch next {
        case .reminder:
            beginHold(.sit)
        case .idleSleep:
            beginHold(.sleep)
        case .coffee:
            beginHold(.coffee)
        case .roam(let coding, let vibe):
            let wasHolding = holding
            holding = false
            self.coding = coding
            self.vibe = vibe
            if wasHolding {
                beginIdle(after: 0.4)
            } else if walkTimer == nil {
                if coding, action == .sit || action == .groom {
                    action = .work
                } else if !coding, action == .work {
                    action = .sit
                }
                emit()
            } else {
                emit()
            }
        }
    }

    private func settleFromCue(afterIdle: Double) {
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(endCheer),
            object: nil
        )
        happyUntil = nil
        switch cue {
        case .reminder:
            beginHold(.sit)
        case .idleSleep:
            beginHold(.sleep)
        case .coffee:
            beginHold(.coffee)
        case .roam(let coding, let vibe):
            self.coding = coding
            self.vibe = vibe
            holding = false
            beginIdle(after: afterIdle)
        }
    }

    private func beginHold(_ next: CatAction) {
        if holding, action == next {
            updatePoseTimer()
            return
        }
        stopMoving()
        holding = true
        vibe = false
        action = next
        blink = false
        frame = 0
        destination = nil
        happyUntil = nil
        emit()
        if next == .sit || next == .coffee {
            perform(#selector(blinkOn), with: nil, afterDelay: 2.2)
        }
    }

    private func startMoving(_ next: CatAction) {
        guard !paused, !hidden else { return }
        cancelIdleSignals()
        action = next
        blink = false
        frame = 0
        frameTick = 0
        guard let point = pickDestination() else {
            beginIdle(after: 1)
            return
        }
        destination = point
        facingLeft = point.x < window.frame.origin.x
        scheduleWalkTimer()
        emit()
    }

    private func beginIdle(after explicit: Double?) {
        guard case .roam = cue else {
            applyCue(cue)
            return
        }
        stopMoving()
        destination = nil
        happyUntil = nil
        blink = false
        holding = false
        let delay: Double
        if coding {
            action = .work
            delay = explicit ?? Double.random(in: 18...40)
            perform(#selector(blinkOn), with: nil, afterDelay: min(2.2, delay * 0.45))
        } else {
            let roll = Double.random(in: 0...1)
            if roll < 0.55 {
                action = .sit
                delay = explicit ?? Double.random(in: 6...16)
                perform(#selector(blinkOn), with: nil, afterDelay: min(2.2, delay * 0.45))
            } else if roll < 0.78 {
                action = .groom
                delay = explicit ?? Double.random(in: 4...9)
            } else {
                action = .sleep
                delay = explicit ?? Double.random(in: 12...28)
            }
        }
        emit()
        perform(#selector(beginWalkFromIdle), with: nil, afterDelay: delay)
    }

    private func stopMoving() {
        walkTimer?.invalidate()
        walkTimer = nil
        poseTimer?.invalidate()
        poseTimer = nil
        destination = nil
        cancelIdleSignals()
    }

    private func cancelIdleSignals() {
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(beginWalkFromIdle),
            object: nil
        )
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(blinkOn),
            object: nil
        )
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(blinkOff),
            object: nil
        )
    }

    private func scheduleWalkTimer() {
        walkTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 12.0, target: self, selector: #selector(step), userInfo: nil, repeats: true)
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        walkTimer = timer
    }

    private func updatePoseTimer() {
        let animating = !paused && !hidden && walkTimer == nil && (
            action == .coffee || action == .work || action == .sleep || action == .happy || vibe
        )
        if animating {
            guard poseTimer == nil else { return }
            let timer = Timer(timeInterval: 0.22, target: self, selector: #selector(poseTick), userInfo: nil, repeats: true)
            timer.tolerance = 0.05
            RunLoop.main.add(timer, forMode: .common)
            poseTimer = timer
        } else {
            poseTimer?.invalidate()
            poseTimer = nil
        }
    }

    private func pickDestination() -> NSPoint? {
        guard let screen = screenContainingCat() else { return nil }
        let area = screen.visibleFrame
        let size = window.frame.size
        let minX = area.minX
        let maxX = area.maxX - size.width
        let minY = area.minY
        let maxY = area.maxY - size.height
        guard maxX > minX + 8, maxY > minY + 8 else { return nil }
        let origin = window.frame.origin
        for _ in 0..<8 {
            let point = NSPoint(
                x: CGFloat.random(in: minX...maxX).rounded(),
                y: CGFloat.random(in: minY...maxY).rounded()
            )
            if hypot(point.x - origin.x, point.y - origin.y) > 80 {
                return point
            }
        }
        return NSPoint(x: maxX, y: minY)
    }

    private var destinationIsOnAScreen: Bool {
        guard let destination else { return false }
        let size = window.frame.size
        let frame = CGRect(origin: destination, size: size)
        return NSScreen.screens.contains { $0.visibleFrame.contains(frame) }
    }

    private func screenContainingCat() -> NSScreen? {
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        return NSScreen.screens.first { $0.visibleFrame.contains(center) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func clampToScreens() {
        var ordered = NSScreen.screens
        if let main = NSScreen.main, let index = ordered.firstIndex(where: { $0 === main }) {
            let screen = ordered.remove(at: index)
            ordered.insert(screen, at: 0)
        }
        let screens = ordered.map(\.visibleFrame)
        guard let next = ScreenClamp.clamped(window.frame, onto: screens) else { return }
        window.setFrame(next, display: true)
    }

    private func emit() {
        updatePoseTimer()
        let pose = CatPose(
            stage: stage(),
            action: action,
            frame: frame,
            facingLeft: facingLeft,
            blink: blink,
            vibe: vibe && action != .sleep
        )
        guard pose != displayedPose else { return }
        displayedPose = pose
        onPose?(pose)
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isInfinite else { return 0 }
        return max(0, width) * max(0, height)
    }
}
