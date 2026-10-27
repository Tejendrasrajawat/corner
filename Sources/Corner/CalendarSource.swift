import AppKit
import CornerKit
import EventKit

enum CalendarAccess {
    case notDetermined, granted, denied
}

struct CalendarInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let source: String
    let colorHex: String?
}

/// Reads meetings from every account in the Calendar app (iCloud, Google, Exchange) via EventKit.
@MainActor
final class CalendarSource {
    private let eventStore = EKEventStore()
    private let store: Store
    private var observer: NSObjectProtocol?
    private var lastLoggedCount = -1

    init(store: Store) {
        self.store = store
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    static var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAccess() {
        // The permission prompt is easy to miss behind other windows while this app is in the background.
        NSApp.activate()
        eventStore.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func refresh() {
        let access = Self.access
        if store.calendarAccess != access { store.calendarAccess = access }
        guard access == .granted else {
            store.setMeetings([])
            return
        }

        let calendars = eventStore.calendars(for: .event)
        let infos = calendars
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, source: $0.source?.title ?? "", colorHex: Self.hex($0.cgColor)) }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
        if store.calendars != infos { store.calendars = infos }

        let prefs = store.state.settings
        let included = calendars.filter { !prefs.excludedCalendarIDs.contains($0.calendarIdentifier) }
        guard prefs.showMeetings, !included.isEmpty else {
            store.setMeetings([])
            return
        }

        // From half a day back (to catch long meetings in progress) to a day and a half ahead.
        let now = Date()
        let predicate = eventStore.predicateForEvents(
            withStart: now.addingTimeInterval(-12 * 3600), end: now.addingTimeInterval(36 * 3600), calendars: included
        )
        let meetings = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled && $0.endDate > now && !Self.declined($0) }
            .sorted { $0.startDate < $1.startDate }
            .map(Self.meeting)
        store.setMeetings(meetings)
        if meetings.count != lastLoggedCount {
            lastLoggedCount = meetings.count
            NSLog("Corner: \(meetings.count) meetings in the next 36 hours from \(included.count) calendars")
        }
    }

    private static func declined(_ event: EKEvent) -> Bool {
        event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
    }

    private static func meeting(_ event: EKEvent) -> Meeting {
        let key = event.eventIdentifier ?? event.calendarItemIdentifier
        let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Meeting(
            id: "\(key)@\(Int(event.startDate.timeIntervalSince1970))",
            title: title.isEmpty ? "Untitled meeting" : title,
            start: event.startDate,
            end: event.endDate,
            calendarTitle: event.calendar?.title ?? "",
            colorHex: hex(event.calendar?.cgColor),
            joinURL: JoinLink.find(in: [event.url?.absoluteString, event.location, event.notes])
        )
    }

    private static func hex(_ color: CGColor?) -> String? {
        guard let color, let c = NSColor(cgColor: color)?.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}
