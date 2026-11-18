import AppKit
import SwiftUI

enum MisoColor {
    static let cream = Color(red: 1.0, green: 0.965, blue: 0.925)
    static let ink = Color(red: 0.29, green: 0.20, blue: 0.16)
    static let accent = Color(red: 0.91, green: 0.55, blue: 0.24)
    static let mute = Color(red: 0.45, green: 0.34, blue: 0.28)
}

struct CarePanel: View {
    var model: AppModel
    var showsClose: Bool

    private var store: PetStore { model.store }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            statusCard
            progress
            taskSection
            reminderSection
            careSection
            footer
        }
        .padding(16)
        .frame(width: 288)
        .foregroundStyle(MisoColor.ink)
        .background(MisoColor.cream)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear {
            model.login.refresh()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            CatPortrait(pose: CatPose(
                stage: store.stage,
                action: store.snapshot.ageAwarded ? .happy : .sit,
                frame: 0,
                facingLeft: false,
                blink: false
            ))
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: nameBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("\(store.stage.title) · \(ageLine)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(MisoColor.mute)
                Text(streakLine)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(MisoColor.accent)
            }
            Spacer(minLength: 0)
            if showsClose {
                Button {
                    model.closeCare()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(MisoColor.mute)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(progressLine)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white)
                    Capsule()
                        .fill(MisoColor.accent)
                        .frame(width: proxy.size.width * progressFraction)
                }
            }
            .frame(height: 8)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.deskLine.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(model.deskLine.detail)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(MisoColor.mute)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
    }

    private var careSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily care")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(MisoColor.mute)
            Text("Feed, water, play, and rest grow the day. Work tasks are separate.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(MisoColor.mute)
            careRow
        }
    }

    private var careRow: some View {
        HStack(spacing: 8) {
            ForEach(CareKind.allCases, id: \.self) { kind in
                CareButton(title: kind.title, symbol: kind.symbol, done: store.isCareDone(kind)) {
                    store.toggleCare(kind)
                }
            }
        }
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(MisoColor.mute)
            if store.snapshot.tasks.isEmpty {
                Text("Check one off and Miso cheers with its name.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(MisoColor.mute)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.snapshot.tasks) { task in
                            HStack(spacing: 8) {
                                Button {
                                    store.toggleTask(task.id)
                                } label: {
                                    Image(systemName: store.isTaskDone(task.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(store.isTaskDone(task.id) ? MisoColor.accent : MisoColor.mute)
                                }
                                .buttonStyle(.plain)
                                Text(task.title)
                                    .font(.system(size: 13, design: .rounded))
                                    .strikethrough(store.isTaskDone(task.id))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button {
                                    store.removeTask(task.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(MisoColor.mute)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
            HStack(spacing: 8) {
                TextField("Add a daily task", text: draftBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
                    .onSubmit(commitDraft)
                Button("Add", action: commitDraft)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(MisoColor.accent))
                    .foregroundStyle(Color.white)
            }
        }
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reminders")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(MisoColor.mute)
            if store.snapshot.reminders.isEmpty {
                Text("Set a time. Miso sits up, and you can snooze or finish it.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(MisoColor.mute)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.snapshot.reminders) { reminder in
                            reminderRow(reminder)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
            HStack(spacing: 8) {
                TextField("Remind me", text: reminderDraftBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
                    .onSubmit(commitReminder)
                DatePicker("Time", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
            }
            HStack(spacing: 8) {
                Toggle("Every day", isOn: reminderRepeatsBinding)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .toggleStyle(.switch)
                    .tint(MisoColor.accent)
                Spacer(minLength: 0)
                Button("Add", action: commitReminder)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(MisoColor.accent))
                    .foregroundStyle(Color.white)
            }
        }
    }

    private func reminderRow(_ reminder: Reminder) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(reminder.title)
                    .font(.system(size: 13, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    Text(reminder.clockText(calendar: store.calendar))
                    if ReminderClock.isDue(reminder, now: Date(), calendar: store.calendar) {
                        Text("Now")
                            .foregroundStyle(MisoColor.accent)
                    }
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(MisoColor.mute)
            }
            Button {
                store.snoozeReminder(reminder.id)
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MisoColor.mute)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Snooze")
            Button {
                store.completeReminder(reminder.id)
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MisoColor.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")
            Button {
                store.removeReminder(reminder.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MisoColor.mute)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete reminder")
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SoftButton(title: model.catPaused ? "Resume" : "Pause") {
                    model.togglePause()
                }
                SoftButton(title: model.catHidden ? "Show" : "Hide 1 hour") {
                    if model.catHidden {
                        model.showCat()
                    } else {
                        model.hideForOneHour()
                    }
                }
            }
            Toggle("Open at login", isOn: Binding(
                get: { model.login.wantsOn },
                set: { model.login.setWantsOn($0) }
            ))
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .toggleStyle(.switch)
            .tint(MisoColor.accent)
            if !model.login.message.isEmpty {
                Text(model.login.message)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(model.login.isError ? Color.red : MisoColor.mute)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Quit Miso") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(MisoColor.mute)
        }
    }

    private var ageLine: String {
        let days = store.snapshot.ageDays
        return days == 1 ? "1 day old" : "\(days) days old"
    }

    private var streakLine: String {
        let streak = store.snapshot.streak
        if streak <= 0 { return "No streak yet" }
        return streak == 1 ? "1-day streak" : "\(streak)-day streak"
    }

    private var progressLine: String {
        if store.snapshot.ageAwarded { return "Grew today" }
        return "\(min(store.pointsToday, PetStore.pointsToGrow)) of \(PetStore.pointsToGrow) to grow today"
    }

    private var progressFraction: CGFloat {
        if store.snapshot.ageAwarded { return 1 }
        return CGFloat(min(store.pointsToday, PetStore.pointsToGrow)) / CGFloat(PetStore.pointsToGrow)
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { store.snapshot.name },
            set: { store.rename($0) }
        )
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { model.taskDraft },
            set: { model.taskDraft = $0 }
        )
    }

    private var reminderDraftBinding: Binding<String> {
        Binding(
            get: { model.reminderDraft },
            set: { model.reminderDraft = $0 }
        )
    }

    private var reminderRepeatsBinding: Binding<Bool> {
        Binding(
            get: { model.reminderRepeats },
            set: { model.reminderRepeats = $0 }
        )
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: { model.reminderTime },
            set: { model.reminderTime = $0 }
        )
    }

    private func commitDraft() {
        store.addTask(title: model.taskDraft)
        model.taskDraft = ""
    }

    private func commitReminder() {
        let title = model.reminderDraft
        let parts = Calendar.current.dateComponents([.hour, .minute], from: model.reminderTime)
        store.addReminder(
            title: title,
            hour: parts.hour ?? 9,
            minute: parts.minute ?? 0,
            repeatsDaily: model.reminderRepeats
        )
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.reminderDraft = ""
        }
    }
}

struct DeskBubble: View {
    var title: String
    var showsActions: Bool
    var onSnooze: () -> Void
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(MisoColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if showsActions {
                HStack(spacing: 8) {
                    Button(action: onSnooze) {
                        Text("Snooze")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white))
                            .foregroundStyle(MisoColor.ink)
                    }
                    .buttonStyle(.plain)
                    Button(action: onDone) {
                        Text("Done")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(MisoColor.accent))
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: 220)
        .background(MisoColor.cream)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CatPortrait: View {
    var pose: CatPose

    var body: some View {
        let picture = CatSprite.picture(for: pose, scale: 2)
        Image(nsImage: NSImage(cgImage: picture.image, size: NSSize(width: 80, height: 80)))
            .interpolation(.high)
            .frame(width: 80, height: 80)
            .accessibilityLabel("Miso")
    }
}

private struct CareButton: View {
    var title: String
    var symbol: String
    var done: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(done ? Color.white : MisoColor.ink)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(done ? MisoColor.accent : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(MisoColor.accent.opacity(done ? 0 : 0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(done ? .isSelected : [])
    }
}

private struct SoftButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white)
                )
                .foregroundStyle(MisoColor.ink)
        }
        .buttonStyle(.plain)
    }
}
