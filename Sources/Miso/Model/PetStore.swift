import Foundation
import Observation

enum CareKind: String, Codable, CaseIterable, Equatable {
    case feed
    case water
    case play
    case rest

    var title: String {
        switch self {
        case .feed: "Feed"
        case .water: "Water"
        case .play: "Play"
        case .rest: "Rest"
        }
    }

    var symbol: String {
        switch self {
        case .feed: "fork.knife"
        case .water: "drop.fill"
        case .play: "tennisball.fill"
        case .rest: "moon.fill"
        }
    }
}

enum CatStage: Equatable {
    case kitten
    case young
    case adult

    var title: String {
        switch self {
        case .kitten: "Small"
        case .young: "Growing"
        case .adult: "Full"
        }
    }

    static func stage(ageDays: Int) -> CatStage {
        if ageDays < 7 { return .kitten }
        if ageDays < 21 { return .young }
        return .adult
    }
}

struct DailyTask: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
}

struct PetSnapshot: Codable, Equatable {
    var name: String
    var ageDays: Int
    var streak: Int
    var day: String
    var care: Set<CareKind>
    var tasks: [DailyTask]
    var doneTaskIDs: Set<UUID>
    var ageAwarded: Bool
    var hideUntil: Date?
    var reminders: [Reminder]

    init(
        name: String,
        ageDays: Int,
        streak: Int,
        day: String,
        care: Set<CareKind>,
        tasks: [DailyTask],
        doneTaskIDs: Set<UUID>,
        ageAwarded: Bool,
        hideUntil: Date?,
        reminders: [Reminder] = []
    ) {
        self.name = name
        self.ageDays = ageDays
        self.streak = streak
        self.day = day
        self.care = care
        self.tasks = tasks
        self.doneTaskIDs = doneTaskIDs
        self.ageAwarded = ageAwarded
        self.hideUntil = hideUntil
        self.reminders = reminders
    }

    private enum CodingKeys: String, CodingKey {
        case name, ageDays, streak, day, care, tasks, doneTaskIDs, ageAwarded, hideUntil, reminders
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        ageDays = try container.decode(Int.self, forKey: .ageDays)
        streak = try container.decode(Int.self, forKey: .streak)
        day = try container.decode(String.self, forKey: .day)
        care = try container.decode(Set<CareKind>.self, forKey: .care)
        tasks = try container.decode([DailyTask].self, forKey: .tasks)
        doneTaskIDs = try container.decode(Set<UUID>.self, forKey: .doneTaskIDs)
        ageAwarded = try container.decode(Bool.self, forKey: .ageAwarded)
        hideUntil = try container.decodeIfPresent(Date.self, forKey: .hideUntil)
        reminders = try container.decodeIfPresent([Reminder].self, forKey: .reminders) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(ageDays, forKey: .ageDays)
        try container.encode(streak, forKey: .streak)
        try container.encode(day, forKey: .day)
        try container.encode(care, forKey: .care)
        try container.encode(tasks, forKey: .tasks)
        try container.encode(doneTaskIDs, forKey: .doneTaskIDs)
        try container.encode(ageAwarded, forKey: .ageAwarded)
        try container.encodeIfPresent(hideUntil, forKey: .hideUntil)
        try container.encode(reminders, forKey: .reminders)
    }

    static func fresh(now: Date, calendar: Calendar) -> PetSnapshot {
        PetSnapshot(
            name: "Miso",
            ageDays: 0,
            streak: 0,
            day: PetStore.dayKey(for: now, calendar: calendar),
            care: [],
            tasks: [],
            doneTaskIDs: [],
            ageAwarded: false,
            hideUntil: nil
        )
    }
}

@Observable
final class PetStore {
    static let pointsToGrow = 4

    private(set) var snapshot: PetSnapshot
    let calendar: Calendar
    private let fileURL: URL?
    var onChange: (() -> Void)?
    var onGrew: (() -> Void)?
    var onCelebrated: ((String) -> Void)?

    init(snapshot: PetSnapshot, calendar: Calendar = .current, fileURL: URL? = nil) {
        self.snapshot = snapshot
        self.calendar = calendar
        self.fileURL = fileURL
    }

    convenience init(fileURL: URL, calendar: Calendar = .current, now: Date = Date()) {
        let snapshot: PetSnapshot
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(PetSnapshot.self, from: data) {
            snapshot = decoded
        } else {
            snapshot = .fresh(now: now, calendar: calendar)
        }
        self.init(snapshot: snapshot, calendar: calendar, fileURL: fileURL)
    }

    static func loadDefault(now: Date = Date()) -> PetStore {
        let url = defaultFileURL()
        return PetStore(fileURL: url, calendar: .current, now: now)
    }

    static func defaultFileURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Miso", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("pet.json")
    }

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    var stage: CatStage {
        CatStage.stage(ageDays: snapshot.ageDays)
    }

    var pointsToday: Int {
        snapshot.care.count + snapshot.doneTaskIDs.count
    }

    func isCareDone(_ kind: CareKind) -> Bool {
        snapshot.care.contains(kind)
    }

    func isTaskDone(_ id: UUID) -> Bool {
        snapshot.doneTaskIDs.contains(id)
    }

    /// Resets daily care and task checks when the local calendar day changed.
    /// Safe to call again the same morning: a second call does nothing.
    func rolloverIfNeeded(now: Date) {
        let today = Self.dayKey(for: now, calendar: calendar)
        guard snapshot.day != today else { return }

        var next = snapshot
        let continued: Bool
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now) {
            continued = next.ageAwarded && next.day == Self.dayKey(for: yesterday, calendar: calendar)
        } else {
            continued = false
        }
        if !continued {
            next.streak = 0
        }
        next.day = today
        next.care = []
        next.doneTaskIDs = []
        next.ageAwarded = false
        snapshot = next
        publish(grew: false)
    }

    func toggleCare(_ kind: CareKind, now: Date = Date()) {
        rolloverIfNeeded(now: now)
        var next = snapshot
        var grew = false
        if next.care.contains(kind) {
            next.care.remove(kind)
        } else {
            next.care.insert(kind)
            grew = awardIfNeeded(&next)
        }
        snapshot = next
        publish(grew: grew)
    }

    func addTask(title: String, now: Date = Date(), id: UUID = UUID()) {
        rolloverIfNeeded(now: now)
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var next = snapshot
        next.tasks.append(DailyTask(id: id, title: String(trimmed.prefix(80))))
        snapshot = next
        publish(grew: false)
    }

    func toggleTask(_ id: UUID, now: Date = Date()) {
        rolloverIfNeeded(now: now)
        guard snapshot.tasks.contains(where: { $0.id == id }) else { return }
        var next = snapshot
        var grew = false
        let finished: Bool
        if next.doneTaskIDs.contains(id) {
            next.doneTaskIDs.remove(id)
            finished = false
        } else {
            next.doneTaskIDs.insert(id)
            grew = awardIfNeeded(&next)
            finished = true
        }
        snapshot = next
        let title = finished ? next.tasks.first(where: { $0.id == id })?.title : nil
        publish(grew: grew, cheer: title)
    }

    func removeTask(_ id: UUID, now: Date = Date()) {
        rolloverIfNeeded(now: now)
        var next = snapshot
        next.tasks.removeAll { $0.id == id }
        next.doneTaskIDs.remove(id)
        snapshot = next
        publish(grew: false)
    }

    func rename(_ name: String) {
        guard name != snapshot.name else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var next = snapshot
        next.name = String(name.prefix(24))
        snapshot = next
        publish(grew: false)
    }

    func addReminder(
        title: String,
        hour: Int,
        minute: Int,
        repeatsDaily: Bool,
        now: Date = Date(),
        id: UUID = UUID()
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return }
        var next = snapshot
        next.reminders.append(Reminder(
            id: id,
            title: String(trimmed.prefix(80)),
            hour: hour,
            minute: minute,
            repeatsDaily: repeatsDaily,
            createdAt: now,
            snoozeUntil: nil,
            doneDay: nil,
            completed: false
        ))
        snapshot = next
        publish(grew: false)
    }

    func snoozeReminder(_ id: UUID, now: Date = Date(), by interval: TimeInterval = 5 * 60) {
        guard let index = snapshot.reminders.firstIndex(where: { $0.id == id }) else { return }
        var next = snapshot
        next.reminders[index].snoozeUntil = now.addingTimeInterval(interval)
        next.reminders[index].completed = false
        next.reminders[index].doneDay = nil
        snapshot = next
        publish(grew: false)
    }

    func completeReminder(_ id: UUID, now: Date = Date()) {
        guard let index = snapshot.reminders.firstIndex(where: { $0.id == id }) else { return }
        var next = snapshot
        var item = next.reminders[index]
        if item.repeatsDaily {
            let today = Self.dayKey(for: now, calendar: calendar)
            if item.doneDay == today, item.snoozeUntil == nil { return }
            item.doneDay = today
        } else if item.completed, item.snoozeUntil == nil {
            return
        } else {
            item.completed = true
        }
        let title = item.title
        item.snoozeUntil = nil
        next.reminders[index] = item
        snapshot = next
        publish(grew: false, cheer: title)
    }

    func removeReminder(_ id: UUID) {
        guard snapshot.reminders.contains(where: { $0.id == id }) else { return }
        var next = snapshot
        next.reminders.removeAll { $0.id == id }
        snapshot = next
        publish(grew: false)
    }

    func dueReminder(now: Date = Date()) -> Reminder? {
        snapshot.reminders
            .filter { ReminderClock.isDue($0, now: now, calendar: calendar) }
            .min { lhs, rhs in
                let left = ReminderClock.nextFire(lhs, now: now, calendar: calendar) ?? .distantPast
                let right = ReminderClock.nextFire(rhs, now: now, calendar: calendar) ?? .distantPast
                return left < right
            }
    }

    func setHideUntil(_ date: Date?) {
        guard snapshot.hideUntil != date else { return }
        var next = snapshot
        next.hideUntil = date
        snapshot = next
        publish(grew: false)
    }

    func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func awardIfNeeded(_ snapshot: inout PetSnapshot) -> Bool {
        let points = snapshot.care.count + snapshot.doneTaskIDs.count
        guard !snapshot.ageAwarded, points >= Self.pointsToGrow else { return false }
        snapshot.ageAwarded = true
        snapshot.ageDays += 1
        snapshot.streak += 1
        return true
    }

    private func publish(grew: Bool, cheer: String? = nil) {
        save()
        onChange?()
        if grew {
            onGrew?()
        }
        if let cheer {
            onCelebrated?(cheer)
        }
    }
}
