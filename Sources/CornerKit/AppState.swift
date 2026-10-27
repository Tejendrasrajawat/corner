import Foundation

public enum ItemRef: Codable, Hashable, Sendable {
    case timer(UUID)
    case countdown(UUID)
    /// Whichever meeting is next or just started, not one fixed event.
    case meeting
    /// A Claude Code session, by its session ID.
    case claude(String)
    case stopwatch
    case clock

    public var isClaude: Bool {
        if case .claude = self { return true }
        return false
    }
}

public enum AlertEvent: Equatable, Sendable {
    case timerDone(id: UUID, label: String)
    case countdownReached(id: UUID, label: String)
    case meetingSoon(Meeting)
    case claudeNeedsYou(ClaudeSession)
    case claudeDone(ClaudeSession)
}

public enum Tone: Sendable {
    case normal, warning, alert, muted
    /// Claude working: its own color, apart from your timers.
    case working
    /// Claude finished: green, because done isn't overdue.
    case success
}

/// The single thing the minimized quarter circle shows.
public struct CornerFace: Equatable, Sendable {
    public var ref: ItemRef
    public var value: String
    public var label: String
    /// 0...1, drawn as the ring along the curved edge.
    public var progress: Double
    public var tone: Tone
    /// No known end (Claude working): the ring sweeps instead of filling.
    public var indeterminate = false
    /// Set when the idle corner shows a companion instead of the clock.
    public var companion: CompanionKind? = nil
}

public struct AppState: Codable, Equatable, Sendable {
    public var timers: [CTimer]
    public var countdowns: [Countdown]
    public var stopwatch: Stopwatch
    public var pinned: ItemRef?
    public var settings: Preferences
    public var todos: [Todo] = []
    /// From Claude Code hooks; saved so a Corner restart mid-session doesn't lose them.
    public var claudeSessions: [ClaudeSession] = []

    // Calendar data is refetched every minute, so none of it is saved.

    /// Upcoming and in-progress meetings, sorted by start.
    public var meetings: [Meeting] = []
    /// Meetings already announced (id → end), so each one alerts once.
    public var meetingsAlerted: [String: Date] = [:]
    /// Started meetings you've seen by opening the card (id → end), so they stop showing red.
    public var meetingsSeen: [String: Date] = [:]

    enum CodingKeys: String, CodingKey {
        case timers, countdowns, stopwatch, pinned, settings, todos, claudeSessions
    }

    public init(
        timers: [CTimer] = [],
        countdowns: [Countdown] = [],
        stopwatch: Stopwatch = Stopwatch(),
        pinned: ItemRef? = nil,
        settings: Preferences = .standard
    ) {
        self.timers = timers
        self.countdowns = countdowns
        self.stopwatch = stopwatch
        self.pinned = pinned
        self.settings = settings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timers = try c.decodeIfPresent([CTimer].self, forKey: .timers) ?? []
        countdowns = try c.decodeIfPresent([Countdown].self, forKey: .countdowns) ?? []
        stopwatch = try c.decodeIfPresent(Stopwatch.self, forKey: .stopwatch) ?? Stopwatch()
        pinned = try c.decodeIfPresent(ItemRef.self, forKey: .pinned)
        settings = try c.decodeIfPresent(Preferences.self, forKey: .settings) ?? .standard
        todos = try c.decodeIfPresent([Todo].self, forKey: .todos) ?? []
        claudeSessions = try c.decodeIfPresent([ClaudeSession].self, forKey: .claudeSessions) ?? []
    }
}

// MARK: - Ticking

extension AppState {
    /// An alert first noticed this long after it was due (Mac asleep, app closed) is marked
    /// as fired without a chime or notification.
    public static let staleAlert: TimeInterval = 15 * 60

    /// How long a finished one-off countdown stays in the list.
    public static let finishedCountdownLifetime: TimeInterval = 60 * 60

    /// Fires timers and countdowns that are due, rolls repeating countdowns forward and
    /// drops finished one-offs. Returns the alerts to announce.
    public mutating func advance(to now: Date, calendar: Calendar = .current) -> [AlertEvent] {
        var events: [AlertEvent] = []

        for i in timers.indices {
            guard let end = timers[i].endDate, timers[i].firedAt == nil, end <= now else { continue }
            timers[i].firedAt = end
            if now.timeIntervalSince(end) < Self.staleAlert {
                events.append(.timerDone(id: timers[i].id, label: timers[i].label))
            }
        }

        for i in countdowns.indices {
            let c = countdowns[i]
            guard c.target <= now, c.firedAt != c.target else { continue }
            countdowns[i].firedAt = c.target
            countdowns[i].acknowledged = false
            if c.repeatRule != .none {
                var next = c.target
                while next <= now, let n = Recurrence.next(after: next, rule: c.repeatRule, calendar: calendar) {
                    next = n
                }
                countdowns[i].since = c.target
                countdowns[i].target = next
            }
            if now.timeIntervalSince(c.target) < Self.staleAlert {
                events.append(.countdownReached(id: c.id, label: c.label))
            }
        }

        let finished = countdowns
            .filter { $0.repeatRule == .none && now.timeIntervalSince($0.target) > Self.finishedCountdownLifetime }
            .map(\.id)
        if !finished.isEmpty {
            countdowns.removeAll { finished.contains($0.id) }
            if case .countdown(let id)? = pinned, finished.contains(id) { pinned = nil }
        }

        if settings.meetingAlertMinutes >= 0 {
            let lead = TimeInterval(settings.meetingAlertMinutes * 60)
            for m in meetings where meetingsAlerted[m.id] == nil && now >= m.start.addingTimeInterval(-lead) {
                meetingsAlerted[m.id] = m.end
                // Already well under way (app just launched, Mac just woke): note it silently.
                if now < m.start.addingTimeInterval(Self.meetingJoinWindow) && now < m.end {
                    events.append(.meetingSoon(m))
                }
            }
        }
        clearOldDoneTodos(at: now, calendar: calendar)
        clearOldClaudeSessions(at: now)

        // Keep entries until the meeting is long over, even if a refetch briefly drops it.
        meetingsAlerted = meetingsAlerted.filter { now.timeIntervalSince($0.value) < 3600 }
        meetingsSeen = meetingsSeen.filter { now.timeIntervalSince($0.value) < 3600 }
        return events
    }

    /// Ends a countdown before it's due, or puts away one that's been reached. A one-off countdown
    /// leaves the list. A repeating one skips the occurrence it's counting down to and carries on
    /// with the next; while its last occurrence is still going off, closing just stops the alert.
    public mutating func closeCountdown(_ id: UUID, at now: Date, calendar: Calendar = .current) {
        guard let i = countdowns.firstIndex(where: { $0.id == id }) else { return }
        let c = countdowns[i]
        if c.repeatRule != .none {
            if c.isAlerting(at: now) {
                countdowns[i].acknowledged = true
                return
            }
            if let next = c.occurrenceAfterTarget(calendar: calendar) {
                countdowns[i].since = now
                countdowns[i].target = next
                return
            }
        }
        countdowns.remove(at: i)
        if pinned == .countdown(id) { pinned = nil }
    }

    /// Opening the card counts as having seen any reached countdowns and started meetings.
    public mutating func acknowledgeAlerts(at now: Date = Date()) {
        for i in countdowns.indices where countdowns[i].firedAt != nil {
            countdowns[i].acknowledged = true
        }
        for m in meetings where m.start <= now {
            meetingsSeen[m.id] = m.end
        }
        for i in claudeSessions.indices {
            claudeSessions[i].seen = true
        }
    }

    public func workdayProgress(at now: Date) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = settings.primaryZone.timeZone
        let c = cal.dateComponents([.hour, .minute, .second], from: now)
        let minutes = Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) + Double(c.second ?? 0) / 60
        let start = Double(settings.workdayStartMinutes)
        let end = Double(settings.workdayEndMinutes)
        guard end > start else { return 0 }
        return min(1, max(0, (minutes - start) / (end - start)))
    }
}

// MARK: - The corner

extension AppState {
    /// Countdowns closer than this turn amber and can take over the corner.
    public static let soonThreshold: TimeInterval = 15 * 60

    /// A started meeting stays red (and first in line) this long, while you're likely joining.
    public static let meetingJoinWindow: TimeInterval = 5 * 60

    /// Priority: something that just went off, then your scroll pick, then a pin, then the
    /// most urgent running item, then the clock.
    public func face(at now: Date, manual: ItemRef? = nil) -> CornerFace {
        let running = timers.filter(\.isRunning)
        if let t = running.first(where: { $0.isOvertime(at: now) }) { return face(for: t, at: now) }
        // Claude blocked on you stays up until it's answered, even after you've seen it.
        if let s = claudeNeedingYou() { return claudeFace(for: s, at: now) }
        if let c = countdowns.first(where: { $0.isAlerting(at: now) }) { return face(for: c, at: now) }
        if let m = meetings.first(where: { isAlerting($0, at: now) }) { return face(for: m, at: now) }
        if let s = claudeFreshlyDone(at: now) { return claudeFace(for: s, at: now) }
        for ref in [manual, pinned].compactMap({ $0 }) {
            if let f = face(for: ref, at: now) { return f }
        }
        if let t = running.min(by: { $0.remaining(at: now) < $1.remaining(at: now) }) { return face(for: t, at: now) }
        let soonCountdown = countdowns
            .filter {
                let r = $0.remaining(at: now)
                return r > 0 && r < Self.soonThreshold
            }
            .min(by: { $0.target < $1.target })
        let soonMeeting = upcomingMeeting(at: now).flatMap { $0.start.timeIntervalSince(now) < Self.soonThreshold ? $0 : nil }
        switch (soonCountdown, soonMeeting) {
        case let (c?, m?): return c.target <= m.start ? face(for: c, at: now) : face(for: m, at: now)
        case let (c?, nil): return face(for: c, at: now)
        case let (nil, m?): return face(for: m, at: now)
        case (nil, nil): break
        }
        if let s = claudeWorking() { return claudeFace(for: s, at: now) }
        if stopwatch.isRunning { return stopwatchFace(at: now) }
        if let t = timers.first(where: \.hasStarted) { return face(for: t, at: now) }
        return clockFace(at: now)
    }

    /// Nil when the item no longer exists.
    public func face(for ref: ItemRef, at now: Date) -> CornerFace? {
        switch ref {
        case .timer(let id): timers.first { $0.id == id }.map { face(for: $0, at: now) }
        case .countdown(let id): countdowns.first { $0.id == id }.map { face(for: $0, at: now) }
        case .meeting: featuredMeeting(at: now).map { face(for: $0, at: now) }
        case .claude(let id): claudeSessions.first { $0.id == id }.map { claudeFace(for: $0, at: now) }
        case .stopwatch: stopwatch.isActive ? stopwatchFace(at: now) : nil
        case .clock: clockFace(at: now)
        }
    }

    /// The order scrolling over the corner steps through.
    public func cycle(at now: Date) -> [ItemRef] {
        timers.map { ItemRef.timer($0.id) }
            + (featuredMeeting(at: now) == nil ? [] : [.meeting])
            + (settings.showClaude ? claudeCardSessions.map { ItemRef.claude($0.id) } : [])
            + countdowns.sorted { $0.target < $1.target }.map { ItemRef.countdown($0.id) }
            + (stopwatch.isActive ? [.stopwatch] : [])
            + [.clock]
    }

    // MARK: Meetings

    public func upcomingMeeting(at now: Date) -> Meeting? {
        meetings.first { $0.start > now }
    }

    public func currentMeeting(at now: Date) -> Meeting? {
        meetings.first { $0.start <= now && $0.end > now }
    }

    /// Started in the last few minutes and you haven't opened the card since.
    public func isAlerting(_ m: Meeting, at now: Date) -> Bool {
        m.start <= now && m.end > now && now.timeIntervalSince(m.start) < Self.meetingJoinWindow && meetingsSeen[m.id] == nil
    }

    /// What `.meeting` means: one that just started, else the next one, else the one in progress.
    public func featuredMeeting(at now: Date) -> Meeting? {
        meetings.first { isAlerting($0, at: now) } ?? upcomingMeeting(at: now) ?? currentMeeting(at: now)
    }

    /// Text next to the menu bar icon; nil shows the icon alone.
    public func menuBarText(at now: Date) -> String? {
        func short(_ label: String) -> String { label.count > 14 ? String(label.prefix(13)) + "…" : label }
        let running = timers.filter(\.isRunning)
        if let t = running.first(where: { $0.isOvertime(at: now) }) {
            return "\(short(t.label)) \(Format.overtime(-t.remaining(at: now)))"
        }
        let waiting = visibleClaudeSessions.filter { $0.status == .needsYou }.count
        if waiting > 0 {
            return waiting == 1 ? "Claude needs you" : "Claude: \(waiting) need you"
        }
        if let t = running.min(by: { $0.remaining(at: now) < $1.remaining(at: now) }) {
            return "\(short(t.label)) \(Format.remaining(t.remaining(at: now)))"
        }
        if let c = countdowns.first(where: { $0.isAlerting(at: now) }) {
            return "\(short(c.label)) now"
        }
        if let m = meetings.first(where: { isAlerting($0, at: now) }) {
            return "\(short(m.title)) now"
        }
        if let m = upcomingMeeting(at: now), m.start.timeIntervalSince(now) <= 5 * 60 {
            return "\(short(m.title)) \(Format.countdownShort(m.start.timeIntervalSince(now)))"
        }
        if let s = claudeWorking() {
            let others = visibleClaudeSessions.filter { $0.status == .working }.count - 1
            return "Claude \(Format.hms(Int(s.elapsed(at: now))))" + (others > 0 ? " +\(others)" : "")
        }
        return nil
    }

    func face(for m: Meeting, at now: Date) -> CornerFace {
        if isAlerting(m, at: now) {
            let ago = now.timeIntervalSince(m.start)
            return CornerFace(ref: .meeting, value: ago < 60 ? "now" : "+" + Format.countdownShort(ago),
                              label: m.title, progress: 1, tone: .alert)
        }
        if m.start > now {
            let r = m.start.timeIntervalSince(now)
            // The ring fills over the last hour before it starts.
            return CornerFace(ref: .meeting, value: Format.countdownShort(r), label: m.title,
                              progress: min(1, max(0, 1 - r / 3600)), tone: r < Self.soonThreshold ? .warning : .normal)
        }
        return CornerFace(ref: .meeting, value: Format.countdownShort(m.end.timeIntervalSince(now)),
                          label: "\(m.title) ends", progress: m.progress(at: now), tone: .muted)
    }

    func face(for t: CTimer, at now: Date) -> CornerFace {
        let r = t.remaining(at: now)
        if r <= 0 {
            return CornerFace(ref: .timer(t.id), value: Format.overtime(-r), label: "\(t.label) over",
                              progress: 1, tone: t.isRunning ? .alert : .muted)
        }
        return CornerFace(ref: .timer(t.id), value: Format.remaining(r),
                          label: t.isRunning || !t.hasStarted ? t.label : "Paused",
                          progress: t.progress(at: now), tone: t.isRunning ? .normal : .muted)
    }

    func face(for c: Countdown, at now: Date) -> CornerFace {
        if c.isAlerting(at: now), let fired = c.firedAt {
            let ago = now.timeIntervalSince(fired)
            return CornerFace(ref: .countdown(c.id), value: ago < 60 ? "now" : "+" + Format.countdownShort(ago),
                              label: c.label, progress: 1, tone: .alert)
        }
        let r = c.remaining(at: now)
        if r <= 0 {
            return CornerFace(ref: .countdown(c.id), value: "done", label: c.label, progress: 1, tone: .muted)
        }
        return CornerFace(ref: .countdown(c.id), value: Format.countdownShort(r), label: c.label,
                          progress: c.progress(at: now), tone: r < Self.soonThreshold ? .warning : .normal)
    }

    func stopwatchFace(at now: Date) -> CornerFace {
        let e = stopwatch.elapsed(at: now)
        return CornerFace(ref: .stopwatch, value: Format.hms(Int(e)),
                          label: stopwatch.isRunning ? "Stopwatch" : "Paused",
                          progress: e.truncatingRemainder(dividingBy: 60) / 60,
                          tone: stopwatch.isRunning ? .normal : .muted)
    }

    func clockFace(at now: Date) -> CornerFace {
        let zone = settings.primaryZone
        let style = settings.clockStyle
        // 12-hour puts AM/PM on the label line; the value line has no room for it.
        let label = style == .h12 ? "\(Format.period(now, in: zone.timeZone)) · \(zone.label)" : zone.label
        if settings.idleFace == .companion {
            return CornerFace(ref: .clock, value: "", label: settings.companion.name,
                              progress: workdayProgress(at: now), tone: .muted, companion: settings.companion)
        }
        return CornerFace(ref: .clock, value: Format.clock(now, in: zone.timeZone, seconds: false, style: style),
                          label: label, progress: workdayProgress(at: now), tone: .muted)
    }
}
