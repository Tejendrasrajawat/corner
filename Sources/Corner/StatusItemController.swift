import AppKit
import CornerKit

/// The menu bar icon. Shows the running timer next to it, like "Focus 18:42".
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store: Store
    private let ui: UIModel

    init(store: Store, ui: UIModel) {
        self.store = store
        self.ui = ui
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Corner")
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        refresh()
    }

    func refresh() {
        let title = store.state.menuBarText(at: store.now).map { " " + $0 } ?? ""
        if item.button?.title != title { item.button?.title = title }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let prefs = store.state.settings
        menu.addItem(ActionItem("Open Corner") { [ui] in ui.expand() })
        menu.addItem(ActionItem("Quick add…", key: "t", modifiers: [.command, .option]) { [ui] in ui.startQuickAdd() })
        let open = store.state.todos.filter { !$0.isDone }.count
        menu.addItem(ActionItem(open == 0 ? "To-do history…" : "To-do history… (\(open) open)") { [ui] in ui.openHistory() })
        menu.addItem(ActionItem(prefs.hidden ? "Show corner" : "Hide corner", key: "c", modifiers: [.control, .option]) { [store] in
            store.mutate { $0.settings.hidden.toggle() }
        })
        let rest = NSMenuItem(title: "When not in use", action: nil, keyEquivalent: "")
        let restMenu = NSMenu()
        for (title, style) in [("Stay full size", RestStyle.full), ("Shrink, grow on hover", .mini), ("Tuck into the edge", .tucked)] {
            let item = ActionItem(title) { [store] in store.mutate { $0.settings.restStyle = style } }
            item.state = prefs.restStyle == style ? .on : .off
            restMenu.addItem(item)
        }
        rest.submenu = restMenu
        menu.addItem(rest)
        menu.addItem(.separator())
        for minutes in [5, 15, 25, 45] {
            menu.addItem(ActionItem("Start \(minutes) min timer") { [store] in store.startTimer(minutes: minutes) })
        }
        let sw = store.state.stopwatch
        let swTitle = sw.isRunning ? "Pause stopwatch" : (sw.isActive ? "Resume stopwatch" : "Start stopwatch")
        menu.addItem(ActionItem(swTitle) { [store] in store.toggleStopwatch() })
        menu.addItem(.separator())
        menu.addItem(ActionItem("Settings…", key: ",") { [ui] in ui.openSettings() })
        let login = ActionItem("Launch at login") { LoginItem.set(!LoginItem.isEnabled) }
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(ActionItem("Quit Corner", key: "q") { NSApp.terminate(nil) })
    }
}

/// An NSMenuItem that runs a closure.
final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = .command, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func fire() { handler() }
}
