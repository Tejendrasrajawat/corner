import Foundation

/// A calendar event, copied out of EventKit so the corner logic stays testable.
public struct Meeting: Equatable, Identifiable, Sendable {
    /// Event identifier plus start time, because occurrences of a repeating event share an identifier.
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var calendarTitle: String
    /// "#RRGGBB" of the calendar.
    public var colorHex: String?
    public var joinURL: URL?

    public init(id: String, title: String, start: Date, end: Date, calendarTitle: String = "", colorHex: String? = nil, joinURL: URL? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.calendarTitle = calendarTitle
        self.colorHex = colorHex
        self.joinURL = joinURL
    }

    public func progress(at now: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(start) / total))
    }
}

/// Finds a video-call link in an event's URL, location or notes. Google Meet links only reach
/// EventKit through the notes, and Zoom usually puts its link in the location.
public enum JoinLink {
    static let hosts = [
        "zoom.us", "zoom.com", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com", "meet.jit.si", "chime.aws", "gotomeeting.com", "around.co", "app.slack.com",
    ]

    public static func find(in texts: [String?]) -> URL? {
        for text in texts.compactMap({ $0 }) {
            for match in text.matches(of: #/https?://[^\s<>"'()\[\]]+/#) {
                var candidate = String(match.output)
                while let last = candidate.last, ".,;:!?".contains(last) { candidate.removeLast() }
                guard let url = URL(string: candidate), let host = url.host?.lowercased() else { continue }
                if hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return url }
            }
        }
        return nil
    }
}
