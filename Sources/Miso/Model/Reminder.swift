import Foundation

struct Reminder: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var hour: Int
    var minute: Int
    var repeatsDaily: Bool
    var createdAt: Date
    var snoozeUntil: Date?
    var doneDay: String?
    var completed: Bool

    func clockText(calendar: Calendar = .current) -> String {
        var parts = calendar.dateComponents([.year, .month, .day], from: Date())
        parts.hour = hour
        parts.minute = minute
        let when = calendar.date(from: parts) ?? Date()
        let time = when.formatted(date: .omitted, time: .shortened)
        return repeatsDaily ? "\(time) · every day" : time
    }
}

/// Pure schedule for alarms. A one-shot stays due until it is finished.
/// A daily alarm waits until its clock time and, once finished, waits for tomorrow.
enum ReminderClock {
    static func nextFire(_ reminder: Reminder, now: Date, calendar: Calendar) -> Date? {
        if let snooze = reminder.snoozeUntil {
            return snooze
        }
        if reminder.repeatsDaily {
            let todayKey = PetStore.dayKey(for: now, calendar: calendar)
            if reminder.doneDay == todayKey {
                return occurrence(of: reminder, on: now, addingDays: 1, calendar: calendar)
            }
            guard let today = occurrence(of: reminder, on: now, addingDays: 0, calendar: calendar) else {
                return nil
            }
            if today >= reminder.createdAt {
                return today
            }
            return occurrence(of: reminder, on: now, addingDays: 1, calendar: calendar)
        }
        if reminder.completed {
            return nil
        }
        return firstSlot(of: reminder, calendar: calendar)
    }

    static func isDue(_ reminder: Reminder, now: Date, calendar: Calendar) -> Bool {
        guard let fire = nextFire(reminder, now: now, calendar: calendar) else { return false }
        return fire <= now
    }

    private static func firstSlot(of reminder: Reminder, calendar: Calendar) -> Date? {
        guard let createdSlot = occurrence(of: reminder, on: reminder.createdAt, addingDays: 0, calendar: calendar) else {
            return nil
        }
        if createdSlot >= reminder.createdAt {
            return createdSlot
        }
        return occurrence(of: reminder, on: reminder.createdAt, addingDays: 1, calendar: calendar)
    }

    private static func occurrence(
        of reminder: Reminder,
        on day: Date,
        addingDays: Int,
        calendar: Calendar
    ) -> Date? {
        guard let shifted = calendar.date(byAdding: .day, value: addingDays, to: day) else { return nil }
        var parts = calendar.dateComponents([.year, .month, .day], from: shifted)
        parts.hour = reminder.hour
        parts.minute = reminder.minute
        parts.second = 0
        return calendar.date(from: parts)
    }
}
