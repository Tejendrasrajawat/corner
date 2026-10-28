import AppKit
import CornerKit
import SwiftUI

/// Owns the saved state and the one-second tick.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var state: AppState
    @Published private(set) var now = Date()
    @Published var calendarAccess = CalendarAccess.notDetermined
    @Published var calendars: [CalendarInfo] = []
    @Published var claudeHooksInstalled = false

    var onAlert: ([AlertEvent]) -> Void = { _ in }
    var onTick: () -> Void = {}
    var onAdd: () -> Void = {}

    /// Nil for preview stores, which never touch the saved state.
    private let fileURL: URL?
    private var ticker: Timer?

    init(preview state: AppState) {
        self.state = state
        fileURL = nil
    }

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Corner", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("state.json")
        fileURL = file
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(AppState.self, from: data) {
            state = saved
        } else {
            state = AppState()
        }
    }

    /// Ticks on the second boundary so every clock on screen flips together.
    func startTicking() {
        tick()
        let next = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) + 1)
        let timer = Timer(fire: next, interval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func tick() {
        now = Date()
        var next = state
        let events = next.advance(to: now)
        if next != state {
            state = next
            save()
        }
        if !events.isEmpty { onAlert(events) }
        onTick()
    }

    func mutate(_ change: (inout AppState) -> Void) {
        now = Date()
        change(&state)
        save()
    }

    func binding<T>(_ path: WritableKeyPath<AppState, T>) -> Binding<T> {
        Binding(get: { self.state[keyPath: path] }, set: { value in self.mutate { $0[keyPath: path] = value } })
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Actions

    func add(_ entry: ParsedEntry) {
        mutate { s in
            switch entry {
            case let .timer(label, duration):
                s.timers.append(CTimer(label: label, duration: duration, startedAt: now))
            case let .countdown(label, target, rule):
                s.countdowns.append(Countdown(label: label, icon: QuickParse.icon(for: label), target: target, since: now, repeatRule: rule))
                s.countdowns.sort { $0.target < $1.target }
            case .stopwatch:
                s.stopwatch.start(at: now)
            case .todo(let text):
                s.addTodo(text, at: now)
            }
        }
        // A to-do never shows in the corner, so it shouldn't knock your scroll pick off it either.
        if case .todo = entry { return }
        onAdd()
    }

    func toggleTodo(_ id: UUID) { mutate { $0.toggleTodo(id, at: now) } }
    func editTodo(_ id: UUID, text: String) { mutate { $0.editTodo(id, text: text) } }
    func deleteTodo(_ id: UUID) { mutate { $0.deleteTodo(id) } }
    func restoreTodo(_ id: UUID) { mutate { $0.restoreTodo(id) } }
    func moveTodo(_ id: UUID, by offset: Int) { mutate { $0.moveTodo(id, by: offset) } }
    func clearDoneTodos() { mutate { $0.clearDoneTodos(at: now) } }

    func startTimer(minutes: Int) {
        add(.timer(label: "Timer", duration: TimeInterval(minutes * 60)))
    }

    func toggleTimer(_ id: UUID) {
        mutate { s in
            guard let i = s.timers.firstIndex(where: { $0.id == id }) else { return }
            if s.timers[i].isRunning { s.timers[i].pause(at: now) } else { s.timers[i].start(at: now) }
        }
    }

    func resetTimer(_ id: UUID) {
        mutate { s in
            guard let i = s.timers.firstIndex(where: { $0.id == id }) else { return }
            s.timers[i].reset()
        }
    }

    func extendTimer(_ id: UUID, by seconds: TimeInterval) {
        mutate { s in
            guard let i = s.timers.firstIndex(where: { $0.id == id }) else { return }
            s.timers[i].extend(by: seconds, at: now)
        }
    }

    func removeTimer(_ id: UUID) {
        mutate { s in
            s.timers.removeAll { $0.id == id }
            if s.pinned == .timer(id) { s.pinned = nil }
        }
    }

    func removeCountdown(_ id: UUID) {
        mutate { s in
            s.countdowns.removeAll { $0.id == id }
            if s.pinned == .countdown(id) { s.pinned = nil }
        }
    }

    func closeCountdown(_ id: UUID) {
        mutate { $0.closeCountdown(id, at: now) }
    }

    func togglePin(_ ref: ItemRef) {
        mutate { $0.pinned = $0.pinned == ref ? nil : ref }
    }

    func toggleStopwatch() {
        mutate { s in
            if s.stopwatch.isRunning { s.stopwatch.pause(at: now) } else { s.stopwatch.start(at: now) }
        }
    }

    func lap() {
        mutate { $0.stopwatch.lap(at: now) }
    }

    func resetStopwatch() {
        mutate { s in
            s.stopwatch.reset()
            if s.pinned == .stopwatch { s.pinned = nil }
        }
    }

    func acknowledgeAlerts() {
        let now = Date()
        let unseenCountdown = state.countdowns.contains { $0.firedAt != nil && !$0.acknowledged }
        let unseenMeeting = state.meetings.contains { $0.start <= now && state.meetingsSeen[$0.id] == nil }
        let unseenClaude = state.claudeSessions.contains { !$0.seen }
        guard unseenCountdown || unseenMeeting || unseenClaude else { return }
        mutate { $0.acknowledgeAlerts(at: now) }
    }

    /// Meetings aren't saved, so this skips the write.
    func setMeetings(_ meetings: [Meeting]) {
        guard meetings != state.meetings else { return }
        state.meetings = meetings
    }

    /// Applies hook events in the order they happened. Alerts only go out for events read
    /// promptly, so starting Corner after a while away doesn't replay old ones.
    func applyClaude(_ items: [(time: Date?, event: ClaudeEvent)]) {
        guard !items.isEmpty else { return }
        let now = Date()
        var alerts: [AlertEvent] = []
        mutate { s in
            for item in items {
                let time = min(item.time ?? now, now)
                if let alert = s.apply(item.event, at: time), now.timeIntervalSince(time) < 120 { alerts.append(alert) }
            }
        }
        if !alerts.isEmpty && state.settings.showClaude { onAlert(alerts) }
    }

    func dismissClaude(_ id: String) {
        mutate { s in
            s.claudeSessions.removeAll { $0.id == id }
            if s.pinned == .claude(id) { s.pinned = nil }
        }
    }

    func setClaudeChats(_ chats: [String: ClaudeChat]) {
        var next = state
        guard next.setClaudeChats(chats) else { return }
        mutate { $0 = next }
    }

    func reconcileClaude(_ turns: [String: ClaudeTranscript.Turn]) {
        var next = state
        guard next.reconcileClaude(turns, at: Date()) else { return }
        mutate { $0 = next }
    }

    func clearDoneClaude() {
        mutate { $0.clearDoneClaudeSessions() }
    }

    func toggleCalendar(_ id: String) {
        mutate { s in
            if let i = s.settings.excludedCalendarIDs.firstIndex(of: id) {
                s.settings.excludedCalendarIDs.remove(at: i)
            } else {
                s.settings.excludedCalendarIDs.append(id)
            }
        }
    }
}

/// UI-only state shared by the panel and its SwiftUI views.
@MainActor
final class UIModel: ObservableObject {
    @Published var expanded = false
    @Published var cardScale: CGFloat = 1
    @Published var cardOpacity: Double = 1
    @Published var hovering = false
    /// Shrunk to a dot at the edge (tuck-away mode, pointer elsewhere).
    @Published var tucked = false
    /// Resting small (shrink mode, pointer elsewhere); grows to full size on hover.
    @Published var shrunk = false
    @Published var quickAddActive = false
    /// The to-do being renamed in place on the card.
    @Published var editingTodo: UUID?
    /// What scrolling over the corner picked; not saved.
    @Published var manual: ItemRef?
    /// A drag of the corner just ended, so the click that comes with it shouldn't open the card.
    var justDragged = false

    /// Typing somewhere on the card, so it shouldn't close itself.
    var isTyping: Bool { quickAddActive || editingTodo != nil }

    var expand: () -> Void = {}
    var collapse: () -> Void = {}
    var startQuickAdd: () -> Void = {}
    var endQuickAdd: () -> Void = {}
    var openSettings: () -> Void = {}
    var connectCalendar: () -> Void = {}
    var openHistory: () -> Void = {}
    var editTodo: (UUID) -> Void = { _ in }
    var endEditing: () -> Void = {}
    var cardSizeChanged: (CGSize) -> Void = { _ in }
}
