import AppKit

/// Listens for a calendar-day change and for wake, then asks the store to roll over.
/// There is no midnight timer: a lid closed at night still rolls the day on wake.
final class DayWatch: NSObject {
    private var store: PetStore?

    func start(store: PetStore) {
        self.store = store
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dayMayHaveChanged),
            name: .NSCalendarDayChanged,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(dayMayHaveChanged),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        store.rolloverIfNeeded(now: Date())
    }

    @objc private func dayMayHaveChanged() {
        if !Thread.isMainThread {
            perform(#selector(dayMayHaveChanged), on: Thread.main, with: nil, waitUntilDone: false)
            return
        }
        store?.rolloverIfNeeded(now: Date())
    }
}
