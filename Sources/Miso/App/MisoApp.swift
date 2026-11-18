import AppKit
import Observation
import ServiceManagement
import SwiftUI

enum LoginRegistration: Equatable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound

    enum Action: Equatable {
        case none
        case register
        case unregister
    }

    /// Register only from an explicit on-toggle when nothing is registered yet.
    /// An already-enabled or waiting item is left alone so rebuilds cannot duplicate it.
    static func action(wantsOn: Bool, status: LoginRegistration) -> Action {
        if wantsOn {
            switch status {
            case .enabled, .requiresApproval:
                return .none
            case .notRegistered, .notFound:
                return .register
            }
        }
        switch status {
        case .enabled, .requiresApproval:
            return .unregister
        case .notRegistered, .notFound:
            return .none
        }
    }

    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notRegistered: self = .notRegistered
        case .notFound: self = .notFound
        @unknown default: self = .notFound
        }
    }
}

@MainActor
@Observable
final class LoginItemController {
    var wantsOn = false
    var message = ""
    var isError = false

    func refresh() {
        switch LoginRegistration(SMAppService.mainApp.status) {
        case .enabled:
            wantsOn = true
            message = "Opens when you log in."
            isError = false
        case .requiresApproval:
            wantsOn = true
            message = "Waiting for approval in System Settings → Login Items."
            isError = false
        case .notRegistered, .notFound:
            wantsOn = false
            if !isError {
                message = ""
            }
        }
    }

    func setWantsOn(_ on: Bool) {
        let decision = LoginRegistration.action(
            wantsOn: on,
            status: LoginRegistration(SMAppService.mainApp.status)
        )
        do {
            switch decision {
            case .none:
                break
            case .register:
                try SMAppService.mainApp.register()
            case .unregister:
                try SMAppService.mainApp.unregister()
            }
            isError = false
            message = ""
        } catch {
            isError = true
            message = error.localizedDescription
        }
        refresh()
    }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let store: PetStore
    let login = LoginItemController()
    var catPaused = false
    var catHidden = false
    var taskDraft = ""
    var reminderDraft = ""
    var reminderRepeats = false
    var reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    var deskLine = DeskPolicy.line(
        cue: .roam(coding: false, vibe: false),
        workSeconds: 0,
        coffeeRemaining: 0
    )

    private var controller: CatController?
    private let dayWatch = DayWatch()
    private var started = false

    private init() {
        store = PetStore.loadDefault()
    }

    func start() {
        guard !started else { return }
        started = true
        dayWatch.start(store: store)
        login.refresh()
        let controller = CatController(model: self)
        self.controller = controller
        controller.start()
    }

    func togglePause() {
        controller?.togglePause()
    }

    func hideForOneHour() {
        controller?.hideForOneHour()
    }

    func showCat() {
        controller?.showCat()
    }

    func closeCare() {
        controller?.closeCare()
    }
}

@main
struct MisoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            CarePanel(model: AppModel.shared, showsClose: false)
        } label: {
            Image(systemName: "cube.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.start()
    }
}
