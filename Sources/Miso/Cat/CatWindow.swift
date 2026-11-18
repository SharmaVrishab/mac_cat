import AppKit
import SwiftUI

final class CatPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class CareWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CatController: NSObject {
    private let model: AppModel
    private let store: PetStore
    private let panel: CatPanel
    private let view: CatView
    private let behavior: CatBehavior
    private let careWindow: CareWindow
    private let careHost: NSHostingView<CarePanel>
    private let bubbleWindow: CareWindow
    private let bubbleHost: NSHostingView<DeskBubble>
    private let desk = DeskWatch()
    private var cheerTitle: String?
    private var cheerTimer: Timer?

    init(model: AppModel) {
        self.model = model
        self.store = model.store
        let size = NSSize(width: CatMetrics.side, height: CatMetrics.side)
        let panel = CatPanel(
            contentRect: NSRect(origin: Self.initialOrigin(size: size), size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        Self.configure(panel, level: .statusBar, stationary: true)

        let view = CatView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = false
        view.autoresizingMask = [.width, .height]
        panel.contentView = view

        let behavior = CatBehavior(window: panel)
        behavior.stage = { [store] in store.stage }

        let careHost = NSHostingView(rootView: CarePanel(model: model, showsClose: true))
        careHost.frame = NSRect(x: 0, y: 0, width: 300, height: 540)
        let careWindow = CareWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 540),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        Self.configure(careWindow, level: Self.overlayLevel, stationary: false)
        careWindow.contentView = careHost

        let bubbleHost = NSHostingView(rootView: DeskBubble(title: "", showsActions: false, onSnooze: {}, onDone: {}))
        bubbleHost.frame = NSRect(x: 0, y: 0, width: 220, height: 84)
        let bubbleWindow = CareWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 84),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        Self.configure(bubbleWindow, level: Self.overlayLevel, stationary: false)
        bubbleWindow.contentView = bubbleHost

        self.panel = panel
        self.view = view
        self.behavior = behavior
        self.careHost = careHost
        self.careWindow = careWindow
        self.bubbleHost = bubbleHost
        self.bubbleWindow = bubbleWindow
        super.init()

        view.onClick = { [weak self] in
            self?.behavior.userReleased()
            self?.toggleCare()
        }
        view.onDragBegan = { [weak self] in
            self?.behavior.userGrabbed()
        }
        view.onDragEnded = { [weak self] in
            self?.behavior.userReleased()
        }
        view.onRightClick = { [weak self] event in
            self?.showMenu(event)
        }
        behavior.onPose = { [weak view] pose in
            view?.show(pose: pose)
        }
        behavior.onPausedChange = { [weak model] paused in
            model?.catPaused = paused
        }
        behavior.onHiddenChange = { [weak self] hidden in
            guard let self else { return }
            self.model.catHidden = hidden
            if !hidden {
                self.store.setHideUntil(nil)
            }
        }
        store.onChange = { [weak self] in
            self?.behavior.noteStageChanged()
            self?.layoutCareIfVisible()
            self?.pushDesk(nil)
        }
        store.onGrew = { [weak self] in
            self?.behavior.playCheer()
        }
        store.onCelebrated = { [weak self] title in
            self?.showCheer(title)
        }
    }

    func start() {
        let until = store.snapshot.hideUntil
        if let until, until <= Date() {
            store.setHideUntil(nil)
        }
        behavior.start(hiddenUntil: store.snapshot.hideUntil)
        model.catHidden = behavior.hidden
        model.catPaused = behavior.paused
        desk.onSample = { [weak self] sample in
            self?.pushDesk(sample)
        }
        desk.start()
    }

    func togglePause() {
        if behavior.paused {
            behavior.resume()
        } else {
            behavior.pause()
        }
    }

    func hideForOneHour() {
        let until = Date().addingTimeInterval(60 * 60)
        store.setHideUntil(until)
        behavior.hide(for: 60 * 60)
    }

    func showCat() {
        behavior.show()
    }

    func closeCare() {
        careWindow.orderOut(nil)
    }

    private func pushDesk(_ sample: DeskSample?) {
        var sample = sample ?? desk.latest
        let due = store.dueReminder(now: Date())
        sample.reminderDue = due != nil
        if due != nil, behavior.hidden {
            behavior.show()
        }
        behavior.noteDesk(sample)
        model.deskLine = DeskPolicy.line(
            cue: DeskPolicy.cue(sample),
            workSeconds: sample.workSeconds,
            coffeeRemaining: sample.coffeeRemaining
        )
        updateBubble(due)
    }

    private func showCheer(_ title: String) {
        behavior.playCheer()
        cheerTitle = title
        updateBubble(store.dueReminder(now: Date()))
        cheerTimer?.invalidate()
        let timer = Timer(timeInterval: 3.5, target: self, selector: #selector(clearCheer), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
        cheerTimer = timer
    }

    @objc private func clearCheer() {
        cheerTitle = nil
        cheerTimer = nil
        updateBubble(store.dueReminder(now: Date()))
    }

    private func updateBubble(_ due: Reminder?) {
        if let due {
            presentBubble(DeskBubble(
                title: due.title,
                showsActions: true,
                onSnooze: { [weak self] in
                    self?.store.snoozeReminder(due.id)
                },
                onDone: { [weak self] in
                    self?.store.completeReminder(due.id)
                }
            ), minimumHeight: 84)
            return
        }
        if let cheerTitle {
            presentBubble(DeskBubble(
                title: "Done · \(cheerTitle)",
                showsActions: false,
                onSnooze: {},
                onDone: {}
            ), minimumHeight: 44)
            return
        }
        bubbleWindow.orderOut(nil)
    }

    private func presentBubble(_ bubble: DeskBubble, minimumHeight: CGFloat) {
        bubbleHost.rootView = bubble
        bubbleHost.layoutSubtreeIfNeeded()
        var size = bubbleHost.fittingSize
        if size.width < 180 { size.width = 220 }
        if size.height < minimumHeight { size.height = minimumHeight }
        bubbleWindow.setContentSize(size)
        placeBubble()
        bubbleWindow.orderFrontRegardless()
    }

    private func placeBubble() {
        let cat = panel.frame
        let size = bubbleWindow.frame.size
        let screen = NSScreen.screens.first { $0.frame.intersects(cat) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        var origin = NSPoint(x: cat.minX, y: cat.maxY + 8)
        if origin.y + size.height > area.maxY {
            origin.y = cat.minY - size.height - 8
        }
        origin.x = min(max(origin.x, area.minX), max(area.minX, area.maxX - size.width))
        origin.y = min(max(origin.y, area.minY), max(area.minY, area.maxY - size.height))
        bubbleWindow.setFrameOrigin(origin)
    }

    func toggleCare() {
        if careWindow.isVisible {
            closeCare()
            return
        }
        layoutCareIfVisible(force: true)
        placeCareWindow()
        careWindow.orderFrontRegardless()
    }

    private func layoutCareIfVisible(force: Bool = false) {
        guard force || careWindow.isVisible else { return }
        careHost.layoutSubtreeIfNeeded()
        var size = careHost.fittingSize
        if size.width < 240 { size.width = 300 }
        if size.height < 280 { size.height = 540 }
        size.width = min(size.width, 340)
        size.height = min(size.height, 820)
        careWindow.setContentSize(size)
    }

    private func placeCareWindow() {
        let cat = panel.frame
        let size = careWindow.frame.size
        let screen = NSScreen.screens.first { $0.frame.intersects(cat) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        var origin = NSPoint(x: cat.maxX + 8, y: cat.minY)
        if origin.x + size.width > area.maxX {
            origin.x = cat.minX - size.width - 8
        }
        origin.x = min(max(origin.x, area.minX), max(area.minX, area.maxX - size.width))
        origin.y = min(max(origin.y, area.minY), max(area.minY, area.maxY - size.height))
        careWindow.setFrameOrigin(origin)
    }

    private func showMenu(_ event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Care", action: #selector(menuCare), keyEquivalent: "")
        menu.addItem(
            withTitle: behavior.paused ? "Resume" : "Pause",
            action: #selector(menuPause),
            keyEquivalent: ""
        )
        menu.addItem(withTitle: "Hide for an hour", action: #selector(menuHide), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Miso", action: #selector(menuQuit), keyEquivalent: "")
        for item in menu.items {
            item.target = self
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func menuCare() {
        behavior.userReleased()
        if !careWindow.isVisible {
            toggleCare()
        }
    }

    @objc private func menuPause() {
        togglePause()
    }

    @objc private func menuHide() {
        hideForOneHour()
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    private static let overlayLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

    /// Shared flags for the cat, care, and bubble panels. The cat stays at
    /// status-bar level and includes `.stationary`. Care and the bubble sit
    /// one level higher and can become key.
    private static func configure(_ panel: NSPanel, level: NSWindow.Level, stationary: Bool) {
        panel.isFloatingPanel = true
        panel.level = level
        var behavior: NSWindow.CollectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .transient,
        ]
        if stationary {
            behavior.insert(.stationary)
        }
        panel.collectionBehavior = behavior
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isRestorable = false
        panel.animationBehavior = .none
    }

    private static func initialOrigin(size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return NSPoint(x: 80, y: 80)
        }
        let area = screen.visibleFrame
        return NSPoint(
            x: (area.maxX - size.width - 48).rounded(),
            y: (area.minY + 32).rounded()
        )
    }
}
