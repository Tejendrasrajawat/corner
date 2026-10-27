import Foundation

public struct ZoneClock: Codable, Equatable, Hashable, Sendable {
    /// A TimeZone identifier such as "Asia/Kolkata".
    public var id: String
    public var label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }

    public var timeZone: TimeZone { TimeZone(identifier: id) ?? .current }

    /// macOS reports India as "GMT+5:30", so IST is special-cased; other zones use the system abbreviation.
    public static func defaultLabel(for id: String) -> String {
        if ["Asia/Kolkata", "Asia/Calcutta"].contains(id) { return "IST" }
        if id == "UTC" || id == "GMT" { return id }
        return TimeZone(identifier: id)?.abbreviation() ?? id
    }
}

public enum CornerSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large

    /// Radius of the quarter circle in points.
    public var points: Double {
        switch self {
        case .small: 84
        case .medium: 100
        case .large: 120
        }
    }

    /// Radius while shrunk at rest: still big enough to read the value.
    public var miniPoints: Double { max(40, points * 0.45) }
}

public enum ClockStyle: String, Codable, CaseIterable, Sendable {
    case h24, h12

    public init(from decoder: Decoder) throws {
        self = ClockStyle(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .h24
    }
}

/// What the corner does while you're not using it.
public enum RestStyle: String, Codable, CaseIterable, Sendable {
    /// Full size all the time.
    case full
    /// A small quarter that grows to full size when the pointer reaches it.
    case mini
    /// A dot at the edge, so the window controls under it stay clickable; push into the edge to bring it out.
    case tucked

    public init(from decoder: Decoder) throws {
        self = RestStyle(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .full
    }
}

public enum ThemeID: String, Codable, CaseIterable, Sendable {
    case system, ocean, sunset, forest, lavender, aurora, midnight

    /// A theme that no longer exists falls back to the default rather than failing the whole state file.
    public init(from decoder: Decoder) throws {
        self = ThemeID(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .system
    }
}

/// Which corner of the screen the widget lives in.
public enum ScreenCorner: String, Codable, CaseIterable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    public var isRight: Bool { self == .topRight || self == .bottomRight }
    public var isBottom: Bool { self == .bottomLeft || self == .bottomRight }

    public var name: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }

    /// The corner nearest a point, given whether it's in the right and the bottom half of the screen.
    public static func nearest(right: Bool, bottom: Bool) -> ScreenCorner {
        switch (right, bottom) {
        case (false, false): .topLeft
        case (true, false): .topRight
        case (false, true): .bottomLeft
        case (true, true): .bottomRight
        }
    }

    public init(from decoder: Decoder) throws {
        self = ScreenCorner(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .topLeft
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var primaryZone: ZoneClock
    public var secondaryZones: [ZoneClock]
    /// Minutes after midnight in the primary zone.
    public var workdayStartMinutes: Int
    public var workdayEndMinutes: Int
    public var cornerSize: CornerSize
    /// 0 keeps the card open until you close it.
    public var autoCollapseSeconds: Int
    public var chime: Bool
    public var notify: Bool
    public var showMeetings: Bool
    /// Minutes before a meeting to chime and notify; 0 is when it starts, -1 is off.
    public var meetingAlertMinutes: Int
    /// EventKit calendar identifiers to leave out, e.g. a personal calendar.
    public var excludedCalendarIDs: [String]
    public var restStyle: RestStyle
    /// Off screen entirely; the menu bar item and alerts keep working.
    public var hidden: Bool
    public var theme: ThemeID
    public var clockStyle: ClockStyle
    /// Off until you set up the Claude Code hooks, since most people don't use Claude Code.
    public var showClaude: Bool
    /// The clock, or a companion character, when nothing else needs the corner.
    public var idleFace: IdleFace
    public var companion: CompanionKind
    public var screenCorner: ScreenCorner

    /// The older on/off tuck setting, still used by the menus' tuck toggle.
    public var tuckAway: Bool {
        get { restStyle == .tucked }
        set { restStyle = newValue ? .tucked : .full }
    }

    public init(
        primaryZone: ZoneClock,
        secondaryZones: [ZoneClock] = [],
        workdayStartMinutes: Int = 600,
        workdayEndMinutes: Int = 1140,
        cornerSize: CornerSize = .medium,
        autoCollapseSeconds: Int = 10,
        chime: Bool = true,
        notify: Bool = true,
        showMeetings: Bool = true,
        meetingAlertMinutes: Int = 1,
        excludedCalendarIDs: [String] = [],
        restStyle: RestStyle = .full,
        hidden: Bool = false,
        theme: ThemeID = .system,
        clockStyle: ClockStyle = .h24,
        showClaude: Bool = false,
        idleFace: IdleFace = .clock,
        companion: CompanionKind = .ninja,
        screenCorner: ScreenCorner = .topLeft
    ) {
        self.primaryZone = primaryZone
        self.secondaryZones = secondaryZones
        self.workdayStartMinutes = workdayStartMinutes
        self.workdayEndMinutes = workdayEndMinutes
        self.cornerSize = cornerSize
        self.autoCollapseSeconds = autoCollapseSeconds
        self.chime = chime
        self.notify = notify
        self.showMeetings = showMeetings
        self.meetingAlertMinutes = meetingAlertMinutes
        self.excludedCalendarIDs = excludedCalendarIDs
        self.restStyle = restStyle
        self.hidden = hidden
        self.theme = theme
        self.clockStyle = clockStyle
        self.showClaude = showClaude
        self.idleFace = idleFace
        self.companion = companion
        self.screenCorner = screenCorner
    }

    /// The Mac's own zone as the main clock, plus UTC.
    public static var standard: Preferences {
        let id = TimeZone.current.identifier
        return Preferences(
            primaryZone: ZoneClock(id: id, label: ZoneClock.defaultLabel(for: id)),
            secondaryZones: id == "UTC" ? [] : [ZoneClock(id: "UTC", label: "UTC")]
        )
    }

    // Missing keys fall back to defaults so older state files keep loading as fields are added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences.standard
        primaryZone = try c.decodeIfPresent(ZoneClock.self, forKey: .primaryZone) ?? d.primaryZone
        secondaryZones = try c.decodeIfPresent([ZoneClock].self, forKey: .secondaryZones) ?? d.secondaryZones
        workdayStartMinutes = try c.decodeIfPresent(Int.self, forKey: .workdayStartMinutes) ?? d.workdayStartMinutes
        workdayEndMinutes = try c.decodeIfPresent(Int.self, forKey: .workdayEndMinutes) ?? d.workdayEndMinutes
        cornerSize = try c.decodeIfPresent(CornerSize.self, forKey: .cornerSize) ?? d.cornerSize
        autoCollapseSeconds = try c.decodeIfPresent(Int.self, forKey: .autoCollapseSeconds) ?? d.autoCollapseSeconds
        chime = try c.decodeIfPresent(Bool.self, forKey: .chime) ?? d.chime
        notify = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? d.notify
        showMeetings = try c.decodeIfPresent(Bool.self, forKey: .showMeetings) ?? d.showMeetings
        meetingAlertMinutes = try c.decodeIfPresent(Int.self, forKey: .meetingAlertMinutes) ?? d.meetingAlertMinutes
        excludedCalendarIDs = try c.decodeIfPresent([String].self, forKey: .excludedCalendarIDs) ?? d.excludedCalendarIDs
        if let rest = try c.decodeIfPresent(RestStyle.self, forKey: .restStyle) {
            restStyle = rest
        } else {
            // Files saved before RestStyle stored tucking as a plain on/off flag.
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            restStyle = try legacy.decodeIfPresent(Bool.self, forKey: .tuckAway) == true ? .tucked : d.restStyle
        }
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? d.hidden
        theme = try c.decodeIfPresent(ThemeID.self, forKey: .theme) ?? d.theme
        clockStyle = try c.decodeIfPresent(ClockStyle.self, forKey: .clockStyle) ?? d.clockStyle
        showClaude = try c.decodeIfPresent(Bool.self, forKey: .showClaude) ?? d.showClaude
        idleFace = try c.decodeIfPresent(IdleFace.self, forKey: .idleFace) ?? d.idleFace
        companion = try c.decodeIfPresent(CompanionKind.self, forKey: .companion) ?? d.companion
        screenCorner = try c.decodeIfPresent(ScreenCorner.self, forKey: .screenCorner) ?? d.screenCorner
    }

    private enum LegacyKeys: String, CodingKey {
        case tuckAway
    }
}
