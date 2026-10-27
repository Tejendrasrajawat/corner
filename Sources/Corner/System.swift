import AppKit
import Carbon.HIToolbox
import CornerKit
import ServiceManagement
import SwiftUI
import UserNotifications

/// System-wide shortcuts. Carbon's RegisterEventHotKey needs no Accessibility permission.
/// One handler serves every shortcut and dispatches on the ID that fired.
final class HotKeys {
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var handlerRef: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue().actions[id.id]?()
            return noErr
        }, 1, &spec, me, &handlerRef)
    }

    /// False when another app already owns the combination.
    @discardableResult
    func register(keyCode: Int, modifiers: Int, action: @escaping () -> Void) -> Bool {
        let id = UInt32(actions.count + 1)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x434F_524E), id: id) // "CORN"
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs.append(ref)
        actions[id] = action
        return true
    }

    deinit {
        refs.forEach { UnregisterEventHotKey($0) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

/// Chime and macOS notification when a timer ends or a countdown is reached.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// UNUserNotificationCenter crashes outside an app bundle, e.g. under `swift run`.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func setUp() {
        guard let center else { return }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func announce(_ events: [AlertEvent], prefs: Preferences) {
        if prefs.chime { NSSound(named: "Glass")?.play() }
        guard prefs.notify, let center else { return }
        for event in events {
            let content = UNMutableNotificationContent()
            switch event {
            case .timerDone(_, let label):
                content.title = "\(label) is done"
                content.body = "Your timer just finished."
            case .countdownReached(_, let label):
                content.title = label
                content.body = "Countdown reached."
            case .meetingSoon(let m):
                let minutes = Int((m.start.timeIntervalSinceNow / 60).rounded())
                content.title = minutes >= 1 ? "\(m.title) in \(minutes) min" : "\(m.title) is starting"
                let times = Format.timeRange(m.start, m.end, in: .current, style: prefs.clockStyle)
                content.body = m.joinURL == nil ? times : "\(times) · Click to join"
                if let url = m.joinURL { content.userInfo = ["joinURL": url.absoluteString] }
            case .claudeNeedsYou(let s):
                content.title = "Claude needs you · \(s.name)"
                content.body = s.detail ?? "Claude is waiting for you."
                content.userInfo = Self.chatInfo(s)
            case .claudeDone(let s):
                content.title = "Claude finished · \(s.name)"
                content.userInfo = Self.chatInfo(s)
                let took = Format.countdownLong(s.elapsed(at: Date()))
                content.body = s.reply.map { "\($0) · \(took)" } ?? s.prompt.map { "“\($0)” · \(took)" } ?? "Took \(took)."
            }
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    private static func chatInfo(_ s: ClaudeSession) -> [String: String] {
        var info = ["claudeSession": s.id]
        info["claudeChat"] = s.chatID
        return info
    }

    /// Clicking a meeting notification opens its call link; a Claude one opens the chat.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let link = info["joinURL"] as? String, let url = URL(string: link) {
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        } else if let session = info["claudeSession"] as? String {
            let chat = info["claudeChat"] as? String
            Task { @MainActor in ClaudeBridge.openChat(session: session, chat: chat) }
        }
        completionHandler()
    }
}

enum LoginItem {
    static var isEnabled: Bool {
        Bundle.main.bundleIdentifier != nil && SMAppService.mainApp.status == .enabled
    }

    static func set(_ on: Bool) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Corner: couldn't change the login item: \(error.localizedDescription)")
        }
    }
}

@MainActor
final class SettingsWindowController {
    private let store: Store
    private let connectCalendar: () -> Void
    private let claude: ClaudeBridge
    private var window: NSWindow?

    init(store: Store, connectCalendar: @escaping () -> Void, claude: ClaudeBridge) {
        self.store = store
        self.connectCalendar = connectCalendar
        self.claude = claude
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: SettingsView.width, height: SettingsView.height),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "Corner settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(
                store: store, connectCalendar: connectCalendar,
                setUpClaude: { [claude] in claude.setUp() }, removeClaude: { [claude] in claude.remove() }
            ))
            w.center()
            window = w
        }
        // Someone may have edited settings.json since; show the hooks as they are now.
        claude.refreshInstalled()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
