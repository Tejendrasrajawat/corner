import AppKit
import Carbon.HIToolbox
import Combine
import CornerKit

@main
enum CornerMain {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            _ = NSApplication.shared
            Snapshot.write(to: URL(fileURLWithPath: args[i + 1]))
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // No Dock icon; the corner and the menu bar item are the whole UI.
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store()
    private let ui = UIModel()
    private let notifier = Notifier()
    private var panel: PanelController?
    private var statusItem: StatusItemController?
    private var settings: SettingsWindowController?
    private var history: HistoryWindowController?
    private var calendar: CalendarSource?
    private var claude: ClaudeBridge?
    private let hotKeys = HotKeys()
    private var ticks = 0
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let calendar = CalendarSource(store: store)
        let claude = ClaudeBridge(store: store)
        self.claude = claude
        let settings = SettingsWindowController(store: store, connectCalendar: { calendar.requestAccess() }, claude: claude)
        let panel = PanelController(store: store, ui: ui)
        let statusItem = StatusItemController(store: store, ui: ui)
        self.calendar = calendar
        self.settings = settings
        self.panel = panel
        self.statusItem = statusItem

        let history = HistoryWindowController(store: store)
        self.history = history

        ui.openSettings = { settings.show() }
        ui.openHistory = { history.show() }
        ui.connectCalendar = { calendar.requestAccess() }
        notifier.setUp()

        // Refetch right away when you change which calendars count.
        store.$state
            .map { [$0.settings.showMeetings ? "on" : "off"] + $0.settings.excludedCalendarIDs }
            .removeDuplicates()
            .dropFirst()
            .sink { _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { calendar.refresh() } }
            }
            .store(in: &cancellables)

        store.onAlert = { [weak self] events in
            guard let self else { return }
            self.notifier.announce(events, prefs: self.store.state.settings)
        }
        store.onTick = { [weak self] in
            panel.tick()
            statusItem.refresh()
            // EventKit also announces changes, but a minutely refetch covers sleep and missed notices.
            guard let self else { return }
            self.ticks += 1
            if self.ticks % 60 == 0 { calendar.refresh() }
            claude.drain()
        }
        // Something new should show in the corner rather than whatever you last scrolled to.
        store.onAdd = { [ui] in ui.manual = nil }

        let quickAdd = hotKeys.register(keyCode: kVK_ANSI_T, modifiers: cmdKey | optionKey) {
            MainActor.assumeIsolated { panel.toggleQuickAdd() }
        }
        let hideShow = hotKeys.register(keyCode: kVK_ANSI_C, modifiers: controlKey | optionKey) { [store] in
            MainActor.assumeIsolated { store.mutate { $0.settings.hidden.toggle() } }
        }
        if !quickAdd { NSLog("Corner: ⌥⌘T is taken by another app, so quick add is only in the menu.") }
        if !hideShow { NSLog("Corner: ⌃⌥C is taken by another app, so hide and show are only in the menu.") }

        store.startTicking()

        // `open -a Corner --args --open` starts with the card open.
        if CommandLine.arguments.contains("--open") { panel.expand() }
    }
}
