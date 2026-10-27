import Foundation

/// A count-down timer. Running timers store their end date rather than a ticking
/// counter, so sleep, restarts and missed ticks never make them drift.
public struct CTimer: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    public var duration: TimeInterval
    /// Set while running.
    public var endDate: Date?
    /// Remaining time while paused or not started.
    public var pausedRemaining: TimeInterval
    /// When it reached zero, so the alert fires once.
    public var firedAt: Date?

    public init(id: UUID = UUID(), label: String, duration: TimeInterval, startedAt: Date? = nil) {
        self.id = id
        self.label = label
        self.duration = duration
        self.pausedRemaining = duration
        self.endDate = startedAt.map { $0.addingTimeInterval(duration) }
    }

    public var isRunning: Bool { endDate != nil }
    public var hasStarted: Bool { isRunning || pausedRemaining != duration }

    /// Negative once the timer is in overtime.
    public func remaining(at now: Date) -> TimeInterval {
        endDate.map { $0.timeIntervalSince(now) } ?? pausedRemaining
    }

    public func isOvertime(at now: Date) -> Bool { remaining(at: now) <= 0 }

    public func progress(at now: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, 1 - remaining(at: now) / duration))
    }

    public mutating func start(at now: Date) {
        guard endDate == nil else { return }
        endDate = now.addingTimeInterval(pausedRemaining)
    }

    public mutating func pause(at now: Date) {
        guard let end = endDate else { return }
        pausedRemaining = end.timeIntervalSince(now)
        endDate = nil
    }

    public mutating func reset() {
        endDate = nil
        pausedRemaining = duration
        firedAt = nil
    }

    /// Adds time. In overtime it starts over with only the added time.
    public mutating func extend(by seconds: TimeInterval, at now: Date) {
        if isOvertime(at: now) {
            duration = seconds
            pausedRemaining = seconds
            endDate = isRunning ? now.addingTimeInterval(seconds) : nil
            firedAt = nil
        } else if let end = endDate {
            endDate = end.addingTimeInterval(seconds)
            duration += seconds
        } else {
            pausedRemaining += seconds
            duration += seconds
        }
    }
}

public enum RepeatRule: String, Codable, CaseIterable, Sendable {
    case none, daily, weekdays, weekly
}

public struct Countdown: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    /// SF Symbol name.
    public var icon: String
    public var target: Date
    /// Start of the current interval; the corner ring fills from here to the target.
    public var since: Date
    public var repeatRule: RepeatRule
    /// The occurrence that last fired. For a repeating countdown the target has already moved on.
    public var firedAt: Date?
    public var acknowledged: Bool

    public init(id: UUID = UUID(), label: String, icon: String, target: Date, since: Date, repeatRule: RepeatRule = .none) {
        self.id = id
        self.label = label
        self.icon = icon
        self.target = target
        self.since = since
        self.repeatRule = repeatRule
        self.firedAt = nil
        self.acknowledged = false
    }

    /// How long a reached countdown stays red in the corner unless you open the card.
    public static let alertWindow: TimeInterval = 15 * 60

    public func remaining(at now: Date) -> TimeInterval { target.timeIntervalSince(now) }

    public func progress(at now: Date) -> Double {
        let total = target.timeIntervalSince(since)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(since) / total))
    }

    public func isAlerting(at now: Date) -> Bool {
        guard let fired = firedAt, !acknowledged else { return false }
        return now.timeIntervalSince(fired) < Countdown.alertWindow
    }

    /// For a repeating countdown, the occurrence after the one it's counting down to.
    public func occurrenceAfterTarget(calendar: Calendar = .current) -> Date? {
        Recurrence.next(after: target, rule: repeatRule, calendar: calendar)
    }
}

public enum Recurrence {
    public static func next(after date: Date, rule: RepeatRule, calendar: Calendar) -> Date? {
        switch rule {
        case .none:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date)
        case .weekdays:
            var d = date
            repeat {
                guard let n = calendar.date(byAdding: .day, value: 1, to: d) else { return nil }
                d = n
            } while isWeekend(d, calendar: calendar)
            return d
        }
    }

    /// Saturday or Sunday, whatever the locale's own idea of a weekend.
    public static func isWeekend(_ date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }
}

public struct Stopwatch: Codable, Equatable, Sendable {
    public var startedAt: Date?
    public var accumulated: TimeInterval = 0
    /// Total elapsed time at each lap press.
    public var laps: [TimeInterval] = []

    public init() {}

    public var isRunning: Bool { startedAt != nil }
    public var isActive: Bool { isRunning || accumulated > 0 }

    public func elapsed(at now: Date) -> TimeInterval {
        accumulated + (startedAt.map { now.timeIntervalSince($0) } ?? 0)
    }

    public mutating func start(at now: Date) {
        if startedAt == nil { startedAt = now }
    }

    public mutating func pause(at now: Date) {
        guard let start = startedAt else { return }
        accumulated += now.timeIntervalSince(start)
        startedAt = nil
    }

    public mutating func lap(at now: Date) {
        guard isRunning else { return }
        laps.append(elapsed(at: now))
    }

    public mutating func reset() {
        self = Stopwatch()
    }
}
