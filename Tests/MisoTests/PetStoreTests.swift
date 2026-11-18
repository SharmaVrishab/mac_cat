import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Miso

struct PetStoreTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func key(_ date: Date) -> String {
        PetStore.dayKey(for: date, calendar: calendar)
    }

    private func store(
        on day: Date,
        age: Int = 0,
        streak: Int = 0,
        care: Set<CareKind> = [],
        tasks: [DailyTask] = [],
        done: Set<UUID> = [],
        awarded: Bool = false,
        fileURL: URL? = nil
    ) -> PetStore {
        let snapshot = PetSnapshot(
            name: "Miso",
            ageDays: age,
            streak: streak,
            day: key(day),
            care: care,
            tasks: tasks,
            doneTaskIDs: done,
            ageAwarded: awarded,
            hideUntil: nil
        )
        return PetStore(snapshot: snapshot, calendar: calendar, fileURL: fileURL)
    }

    @Test func overnightRolloverTwiceDoesNotDoubleReset() {
        let task = DailyTask(id: UUID(), title: "Write")
        let yesterday = date(2026, 10, 17, 23)
        let morning = date(2026, 10, 18, 9)
        let pet = store(
            on: yesterday,
            age: 4,
            streak: 3,
            care: [.feed, .water],
            tasks: [task],
            done: [task.id],
            awarded: false
        )

        pet.rolloverIfNeeded(now: morning)
        let once = pet.snapshot
        pet.rolloverIfNeeded(now: morning)

        #expect(pet.snapshot == once)
        #expect(once.day == key(morning))
        #expect(once.care.isEmpty)
        #expect(once.doneTaskIDs.isEmpty)
        #expect(once.tasks == [task])
        #expect(once.streak == 0)
        #expect(once.ageDays == 4)
        #expect(once.ageAwarded == false)
    }

    @Test func caredYesterdayKeepsStreak() {
        let yesterday = date(2026, 10, 17)
        let morning = date(2026, 10, 18, 9)
        let pet = store(on: yesterday, age: 10, streak: 4, awarded: true)

        pet.rolloverIfNeeded(now: morning)
        let once = pet.snapshot
        pet.rolloverIfNeeded(now: morning)

        #expect(pet.snapshot == once)
        #expect(once.streak == 4)
        #expect(once.ageDays == 10)
        #expect(once.ageAwarded == false)
        #expect(once.care.isEmpty)
    }

    @Test func gapLongerThanOneDayResetsStreak() {
        let pet = store(on: date(2026, 10, 15), age: 8, streak: 5, awarded: true)
        pet.rolloverIfNeeded(now: date(2026, 10, 18, 9))
        #expect(pet.snapshot.streak == 0)
        #expect(pet.snapshot.ageDays == 8)
        #expect(pet.snapshot.day == key(date(2026, 10, 18)))
    }

    @Test func fourPointsAwardOncePerDay() {
        let today = date(2026, 10, 18, 10)
        let pet = store(on: today)
        pet.toggleCare(.feed, now: today)
        pet.toggleCare(.water, now: today)
        pet.toggleCare(.play, now: today)
        #expect(pet.snapshot.ageDays == 0)
        #expect(pet.snapshot.ageAwarded == false)

        pet.toggleCare(.rest, now: today)
        #expect(pet.snapshot.ageDays == 1)
        #expect(pet.snapshot.streak == 1)
        #expect(pet.snapshot.ageAwarded == true)
        #expect(pet.stage == .kitten)

        let extra = UUID()
        pet.addTask(title: "Inbox", now: today, id: extra)
        pet.toggleTask(extra, now: today)
        #expect(pet.snapshot.ageDays == 1)
        #expect(pet.snapshot.streak == 1)

        pet.toggleCare(.feed, now: today)
        #expect(pet.snapshot.ageDays == 1)
        #expect(pet.snapshot.ageAwarded == true)

        let tomorrow = date(2026, 10, 19, 9)
        pet.rolloverIfNeeded(now: tomorrow)
        pet.rolloverIfNeeded(now: tomorrow)
        #expect(pet.snapshot.ageDays == 1)
        #expect(pet.snapshot.streak == 1)
        #expect(pet.snapshot.ageAwarded == false)

        pet.toggleCare(.feed, now: tomorrow)
        pet.toggleCare(.water, now: tomorrow)
        pet.toggleCare(.play, now: tomorrow)
        pet.toggleCare(.rest, now: tomorrow)
        #expect(pet.snapshot.ageDays == 2)
        #expect(pet.snapshot.streak == 2)
    }

    @Test func tasksAloneCanGrowTheCat() {
        let today = date(2026, 10, 18)
        let pet = store(on: today)
        let ids = (0..<4).map { _ in UUID() }
        for (index, id) in ids.enumerated() {
            pet.addTask(title: "Task \(index)", now: today, id: id)
            pet.toggleTask(id, now: today)
        }
        #expect(pet.snapshot.ageDays == 1)
        #expect(pet.pointsToday == 4)
    }

    @Test func mixedPointsAndCarriedTasks() {
        let today = date(2026, 10, 18)
        let pet = store(on: today)
        let id = UUID()
        pet.addTask(title: "Stretch", now: today, id: id)
        pet.toggleCare(.feed, now: today)
        pet.toggleCare(.water, now: today)
        pet.toggleTask(id, now: today)
        #expect(pet.snapshot.ageDays == 0)
        pet.toggleCare(.play, now: today)
        #expect(pet.snapshot.ageDays == 1)

        pet.rolloverIfNeeded(now: date(2026, 10, 19, 8))
        #expect(pet.snapshot.tasks.map(\.title) == ["Stretch"])
        #expect(pet.isTaskDone(id) == false)
        #expect(pet.snapshot.care.isEmpty)
    }

    @Test func blankTaskAndRename() {
        let pet = store(on: date(2026, 10, 18))
        pet.addTask(title: "   ", now: date(2026, 10, 18))
        #expect(pet.snapshot.tasks.isEmpty)
        pet.rename("   ")
        #expect(pet.snapshot.name == "Miso")
        pet.rename("Mochi")
        #expect(pet.snapshot.name == "Mochi")
    }

    @Test func reloadFromDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("miso-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let today = date(2026, 10, 18)
        let pet = store(on: today, fileURL: url)
        pet.toggleCare(.feed, now: today)
        pet.addTask(title: "Water plants", now: today)
        let loaded = PetStore(fileURL: url, calendar: calendar, now: today)
        #expect(loaded.snapshot.care.contains(.feed))
        #expect(loaded.snapshot.tasks.map(\.title) == ["Water plants"])
        #expect(loaded.snapshot.day == key(today))
    }

    @Test func stages() {
        #expect(CatStage.stage(ageDays: 0) == .kitten)
        #expect(CatStage.stage(ageDays: 6) == .kitten)
        #expect(CatStage.stage(ageDays: 7) == .young)
        #expect(CatStage.stage(ageDays: 20) == .young)
        #expect(CatStage.stage(ageDays: 21) == .adult)
    }

    @Test func loginRegisterOnce() {
        #expect(LoginRegistration.action(wantsOn: true, status: .notRegistered) == .register)
        #expect(LoginRegistration.action(wantsOn: true, status: .notFound) == .register)
        #expect(LoginRegistration.action(wantsOn: true, status: .enabled) == .none)
        #expect(LoginRegistration.action(wantsOn: true, status: .requiresApproval) == .none)
        #expect(LoginRegistration.action(wantsOn: false, status: .enabled) == .unregister)
        #expect(LoginRegistration.action(wantsOn: false, status: .notRegistered) == .none)
    }

    @Test func screenClampBringsCatBackOntoMain() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let stranded = CGRect(x: 3200, y: 200, width: 96, height: 96)
        let clamped = ScreenClamp.clamped(stranded, onto: [main])
        #expect(clamped == CGRect(x: 1440 - 96, y: 200, width: 96, height: 96))

        let inside = CGRect(x: 40, y: 40, width: 96, height: 96)
        #expect(ScreenClamp.clamped(inside, onto: [main]) == nil)
        #expect(ScreenClamp.clamped(stranded, onto: []) == nil)

        let left = CGRect(x: -1800, y: 10, width: 96, height: 96)
        #expect(ScreenClamp.clamped(left, onto: [main])?.origin.x == 0)
    }

    @Test func screenClampPrefersTheScreenTheCatStillTouches() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let external = CGRect(x: 1440, y: 0, width: 800, height: 600)
        let hangingOffExternal = CGRect(x: 2200, y: 40, width: 96, height: 96)
        let clamped = ScreenClamp.clamped(hangingOffExternal, onto: [main, external])
        #expect(clamped == CGRect(x: 2240 - 96, y: 40, width: 96, height: 96))
        #expect(external.contains(clamped ?? .zero))
    }

    @Test func deskCuePutsAlarmsRestAndCoffeeAheadOfRoaming() {
        var sample = DeskSample(
            idleSeconds: 0,
            frontmostBundleID: "com.apple.dt.Xcode",
            musicPlaying: true,
            coffeeBreak: true,
            reminderDue: true
        )
        #expect(DeskPolicy.cue(sample) == .reminder)

        sample.reminderDue = false
        sample.idleSeconds = DeskPolicy.idleSleepAfter
        #expect(DeskPolicy.cue(sample) == .idleSleep)

        sample.idleSeconds = DeskPolicy.idleSleepAfter - 1
        #expect(DeskPolicy.cue(sample) == .coffee)

        sample.coffeeBreak = false
        #expect(DeskPolicy.cue(sample) == .roam(coding: true, vibe: true))

        sample.musicPlaying = false
        sample.frontmostBundleID = "com.apple.Safari"
        #expect(DeskPolicy.cue(sample) == .roam(coding: false, vibe: false))
    }

    @Test func codingAppsAreTheEditorsAndTerminals() {
        #expect(DeskPolicy.isCodingApp("com.apple.dt.Xcode"))
        #expect(DeskPolicy.isCodingApp("com.microsoft.VSCode"))
        #expect(DeskPolicy.isCodingApp("com.apple.Terminal"))
        #expect(DeskPolicy.isCodingApp("com.googlecode.iterm2"))
        #expect(DeskPolicy.isCodingApp("dev.warp.Warp-Stable"))
        #expect(DeskPolicy.isCodingApp("com.todesktop.230313mzl4w4u92"))
        #expect(DeskPolicy.isCodingApp("com.jetbrains.intellij"))
        #expect(DeskPolicy.isCodingApp("com.apple.Safari") == false)
        #expect(DeskPolicy.isCodingApp(nil) == false)
    }

    @Test func coffeeClockPausesForALongIdleAndResetsAfterTheBreak() {
        var clock = DeskClock()
        clock.advance(by: DeskPolicy.coffeeAfter - 20, idleSeconds: 0)
        #expect(clock.onBreak == false)

        clock.advance(by: 10, idleSeconds: DeskPolicy.idleSleepAfter)
        #expect(clock.workSeconds == DeskPolicy.coffeeAfter - 10)
        #expect(clock.onBreak == false)

        let paused = clock.workSeconds
        clock.advance(by: 30, idleSeconds: DeskPolicy.pauseWorkAfterIdle)
        #expect(clock.workSeconds == paused)
        #expect(clock.onBreak == false)

        clock.advance(by: 10, idleSeconds: 0)
        #expect(clock.onBreak)
        #expect(clock.workSeconds >= DeskPolicy.coffeeAfter)

        clock.advance(by: DeskPolicy.coffeeBreak, idleSeconds: 0)
        #expect(clock.onBreak == false)
        #expect(clock.workSeconds == 0)
    }

    @Test func reminderFiresOnceThenSnoozesAndWaitsUntilTomorrow() {
        let created = date(2026, 10, 18, 8)
        var reminder = Reminder(
            id: UUID(),
            title: "Stand up",
            hour: 9,
            minute: 0,
            repeatsDaily: false,
            createdAt: created,
            snoozeUntil: nil,
            doneDay: nil,
            completed: false
        )
        #expect(ReminderClock.isDue(reminder, now: date(2026, 10, 18, 8, minute: 30), calendar: calendar) == false)
        #expect(ReminderClock.nextFire(reminder, now: date(2026, 10, 18, 8, minute: 30), calendar: calendar) == date(2026, 10, 18, 9))
        #expect(ReminderClock.isDue(reminder, now: date(2026, 10, 18, 9, minute: 30), calendar: calendar))

        var later = reminder
        later.createdAt = date(2026, 10, 18, 15)
        #expect(ReminderClock.isDue(later, now: date(2026, 10, 18, 15, minute: 10), calendar: calendar) == false)
        #expect(ReminderClock.nextFire(later, now: date(2026, 10, 18, 15, minute: 10), calendar: calendar) == date(2026, 10, 19, 9))

        reminder.snoozeUntil = date(2026, 10, 18, 9, minute: 35)
        #expect(ReminderClock.isDue(reminder, now: date(2026, 10, 18, 9, minute: 30), calendar: calendar) == false)
        #expect(ReminderClock.isDue(reminder, now: date(2026, 10, 18, 9, minute: 35), calendar: calendar))

        reminder.snoozeUntil = nil
        reminder.completed = true
        #expect(ReminderClock.nextFire(reminder, now: date(2026, 10, 18, 12), calendar: calendar) == nil)

        reminder.completed = false
        reminder.repeatsDaily = true
        reminder.doneDay = key(date(2026, 10, 18))
        #expect(ReminderClock.isDue(reminder, now: date(2026, 10, 18, 18), calendar: calendar) == false)
        #expect(ReminderClock.nextFire(reminder, now: date(2026, 10, 18, 18), calendar: calendar) == date(2026, 10, 19, 9))

        let missed = Reminder(
            id: UUID(),
            title: "Stretch",
            hour: 9,
            minute: 0,
            repeatsDaily: false,
            createdAt: date(2026, 10, 17, 8),
            snoozeUntil: nil,
            doneDay: nil,
            completed: false
        )
        #expect(ReminderClock.isDue(missed, now: date(2026, 10, 18, 10), calendar: calendar))
    }

    @Test func finishingATaskCheersWithItsTitleWithoutGrowing() {
        let today = date(2026, 10, 18)
        let pet = store(on: today)
        let id = UUID()
        pet.addTask(title: "Write tests", now: today, id: id)
        var cheers: [String] = []
        pet.onCelebrated = { cheers.append($0) }

        pet.toggleTask(id, now: today)
        pet.toggleTask(id, now: today)

        #expect(cheers == ["Write tests"])
        #expect(pet.snapshot.ageDays == 0)
        #expect(pet.pointsToday == 0)
    }

    @Test func finishingAReminderCheersWithItsTitle() {
        let morning = date(2026, 10, 18, 8)
        let pet = store(on: morning)
        let id = UUID()
        pet.addReminder(title: "Stand up", hour: 9, minute: 0, repeatsDaily: false, now: morning, id: id)
        var cheers: [String] = []
        pet.onCelebrated = { cheers.append($0) }

        pet.completeReminder(id, now: date(2026, 10, 18, 9))
        pet.completeReminder(id, now: date(2026, 10, 18, 9, minute: 5))

        #expect(cheers == ["Stand up"])
        #expect(pet.snapshot.ageDays == 0)
    }

    @Test func deskStatusNamesEachBehavior() {
        let wandering = DeskPolicy.line(
            cue: .roam(coding: false, vibe: false),
            workSeconds: 18 * 60,
            coffeeRemaining: 0
        )
        #expect(wandering == DeskStatusLine(
            title: "Wandering",
            detail: "Moving between sits and walks. 18 of 45 min toward coffee."
        ))
        #expect(DeskPolicy.line(cue: .roam(coding: true, vibe: false), workSeconds: 0, coffeeRemaining: 0).title == "Coding with you")
        #expect(DeskPolicy.line(cue: .roam(coding: false, vibe: true), workSeconds: 0, coffeeRemaining: 0).title == "Listening")
        #expect(DeskPolicy.line(cue: .roam(coding: true, vibe: true), workSeconds: 0, coffeeRemaining: 0).detail.hasPrefix("Listening along."))
        #expect(DeskPolicy.line(cue: .idleSleep, workSeconds: 0, coffeeRemaining: 0).title == "Napping")
        #expect(DeskPolicy.line(cue: .reminder, workSeconds: 0, coffeeRemaining: 0).title == "Reminder")
        let coffee = DeskPolicy.line(cue: .coffee, workSeconds: 45 * 60, coffeeRemaining: 90)
        #expect(coffee.title == "Coffee break")
        #expect(coffee.detail == "Mug for 3 minutes. 2 min left.")
    }

    @Test func remindersPersistWithoutGrowingTheCatOrDroppingOldSaves() throws {
        let morning = date(2026, 10, 18, 8)
        let pet = store(on: morning)
        pet.addReminder(title: "   ", hour: 9, minute: 0, repeatsDaily: false, now: morning)
        #expect(pet.snapshot.reminders.isEmpty)

        let id = UUID()
        pet.addReminder(title: "Water", hour: 9, minute: 0, repeatsDaily: true, now: morning, id: id)
        #expect(pet.dueReminder(now: date(2026, 10, 18, 8, minute: 30)) == nil)
        #expect(pet.dueReminder(now: date(2026, 10, 18, 9))?.id == id)

        pet.snoozeReminder(id, now: date(2026, 10, 18, 9))
        #expect(pet.dueReminder(now: date(2026, 10, 18, 9)) == nil)
        #expect(pet.dueReminder(now: date(2026, 10, 18, 9, minute: 5))?.id == id)

        pet.completeReminder(id, now: date(2026, 10, 18, 9, minute: 5))
        #expect(pet.dueReminder(now: date(2026, 10, 18, 9, minute: 6)) == nil)
        #expect(pet.snapshot.ageDays == 0)
        #expect(pet.pointsToday == 0)

        pet.rolloverIfNeeded(now: date(2026, 10, 19, 8))
        #expect(pet.snapshot.reminders.map(\.title) == ["Water"])
        #expect(pet.dueReminder(now: date(2026, 10, 19, 9))?.id == id)

        let old = """
        {"ageAwarded":false,"ageDays":3,"care":["feed"],"day":"2026-10-18","doneTaskIDs":[],"name":"Miso","streak":2,"tasks":[]}
        """.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(PetSnapshot.self, from: old)
        #expect(snapshot.reminders.isEmpty)
        #expect(snapshot.ageDays == 3)
        #expect(snapshot.care.contains(.feed))
        #expect(snapshot.streak == 2)
    }

    @Test func spritesAreSmoothAndClickable() throws {
        let actions: [CatAction] = [.walk, .sit, .sleep, .happy, .groom, .work, .coffee]
        let bounds = CGSize(width: CatMetrics.side, height: CatMetrics.side)
        for stage in [CatStage.kitten, .young, .adult] {
            for action in actions {
                let picture = CatSprite.picture(
                    for: CatPose(stage: stage, action: action, frame: 0, facingLeft: false, blink: false),
                    scale: 2
                )
                #expect(picture.width == CatMetrics.side * 2)
                #expect(picture.height == picture.width)
                #expect(picture.containsBody(at: CGPoint(x: 6, y: 6), in: bounds) == false)
                #expect(picture.containsBody(at: CGPoint(x: 80, y: 78), in: bounds))
            }
        }

        let sit = CatSprite.picture(for: CatPose(stage: .young, action: .sit, frame: 0, facingLeft: false, blink: false), scale: 2)
        let sleep = CatSprite.picture(for: CatPose(stage: .young, action: .sleep, frame: 0, facingLeft: false, blink: false), scale: 2)
        let coffee = CatSprite.picture(for: CatPose(stage: .young, action: .coffee, frame: 0, facingLeft: false, blink: false), scale: 2)
        var vibing = CatPose(stage: .young, action: .sit, frame: 1, facingLeft: false, blink: false)
        vibing.vibe = true
        let vibe = CatSprite.picture(for: vibing, scale: 2)
        let sitData = sit.image.dataProvider?.data as Data?
        #expect(sitData != sleep.image.dataProvider?.data as Data?)
        #expect(sitData != coffee.image.dataProvider?.data as Data?)
        #expect(sitData != vibe.image.dataProvider?.data as Data?)

        try writeSheet(to: URL(fileURLWithPath: "/tmp/miso-sheet.png"))
    }

    private func writeSheet(to url: URL) throws {
        let poses: [CatPose] = [
            CatPose(stage: .kitten, action: .sit, frame: 0, facingLeft: false, blink: false),
            CatPose(stage: .kitten, action: .walk, frame: 0, facingLeft: false, blink: false),
            CatPose(stage: .kitten, action: .sleep, frame: 0, facingLeft: false, blink: false),
            CatPose(stage: .young, action: .sit, frame: 0, facingLeft: false, blink: false),
            CatPose(stage: .young, action: .walk, frame: 1, facingLeft: false, blink: false),
            CatPose(stage: .young, action: .happy, frame: 0, facingLeft: false, blink: false),
            CatPose(stage: .adult, action: .sit, frame: 0, facingLeft: false, blink: false),
            CatPose(stage: .adult, action: .walk, frame: 2, facingLeft: true, blink: false),
            CatPose(stage: .adult, action: .groom, frame: 0, facingLeft: false, blink: false),
            CatPose(stage: .adult, action: .work, frame: 1, facingLeft: false, blink: false),
            CatPose(stage: .adult, action: .coffee, frame: 0, facingLeft: false, blink: false),
            CatPose(stage: .adult, action: .sit, frame: 1, facingLeft: false, blink: false, vibe: true),
        ]
        let cell = 220
        let columns = 3
        let rows = Int(ceil(Double(poses.count) / Double(columns)))
        let context = try #require(CGContext(
            data: nil,
            width: columns * cell,
            height: rows * cell,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setAllowsAntialiasing(true)
        context.interpolationQuality = .high
        context.clear(CGRect(x: 0, y: 0, width: columns * cell, height: rows * cell))
        for (index, pose) in poses.enumerated() {
            let picture = CatSprite.picture(for: pose, scale: 2)
            let originX = (index % columns) * cell + 20
            let originY = (rows - 1 - index / columns) * cell + 16
            context.draw(picture.image, in: CGRect(x: originX, y: originY, width: 180, height: 180))
        }
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
