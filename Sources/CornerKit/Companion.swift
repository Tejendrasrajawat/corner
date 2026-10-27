import Foundation

/// What the corner shows when nothing else needs it.
public enum IdleFace: String, Codable, CaseIterable, Sendable {
    case clock
    /// A small character that lives in the corner.
    case companion

    public init(from decoder: Decoder) throws {
        self = IdleFace(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .clock
    }
}

/// The characters you can pick in Settings: original pixel-art characters in the style of desktop
/// mascots, plus a cat.
public enum CompanionKind: String, Codable, CaseIterable, Sendable {
    case ninja, swordsman, mage, cat

    public var name: String {
        switch self {
        case .ninja: "Ninja"
        case .swordsman: "Swordsman"
        case .mage: "Mage"
        case .cat: "Cat"
        }
    }

    public init(from decoder: Decoder) throws {
        self = CompanionKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .ninja
    }
}

/// What the companion is up to.
public enum CompanionActivity: String, CaseIterable, Sendable {
    /// Sitting, breathing, blinking, glancing about.
    case sit
    /// Waving (the cat purrs and bobs).
    case wag
    /// Its own trick: throwing stars, sword practice, a spell, chasing yarn.
    case play
    /// Pacing up and down the corner.
    case walk
    /// Up the screen's edge, along under the menu bar, and a drop back down.
    case climb
    /// Curled up asleep while you're away, or late at night.
    case sleep
    /// Stretching and yawning after a nap.
    case wake
    /// The pointer is on the corner: it hops and sends a heart.
    case greet
}

/// Decides what the companion does from moment to moment. It sleeps while you're away from the
/// keyboard, wakes with a stretch when you come back, greets the pointer, and otherwise picks
/// something to do every several seconds.
public struct CompanionBrain: Sendable {
    public private(set) var activity: CompanionActivity = .sit
    /// When the current activity began; the drawing times its moves from here.
    public private(set) var since: Date
    private var length: TimeInterval
    private var seed: UInt64

    /// Away from the keyboard and mouse this long, it naps.
    public static let napAfter: TimeInterval = 5 * 60
    /// Late at night it dozes off sooner.
    public static let nightNapAfter: TimeInterval = 60
    public static let wakeLength: TimeInterval = 3
    /// One out-and-back walk; walks last a whole number of these so they finish where they started.
    public static let walkLoop: TimeInterval = 4
    /// The climb is one trip that ends back where it started.
    public static let climbLength: TimeInterval = 8

    public init(now: Date, seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        since = now
        self.seed = seed
        length = 0
        length = nextLength(for: .sit)
    }

    /// Seconds into the current activity.
    public func elapsed(at now: Date) -> TimeInterval { max(0, now.timeIntervalSince(since)) }

    /// Moves on to `now`. `away` is how long since the last key press or mouse move, `hour` the
    /// local hour (0-23), and `hovering` whether the pointer is over the corner.
    @discardableResult
    public mutating func update(now: Date, away: TimeInterval, hour: Int, hovering: Bool) -> CompanionActivity {
        if hovering {
            if activity != .greet { start(.greet, at: now) }
            return activity
        }
        let night = hour < 6
        if away >= (night ? Self.nightNapAfter : Self.napAfter) {
            if activity != .sleep { start(.sleep, at: now) }
            return activity
        }
        switch activity {
        case .sleep:
            start(.wake, at: now)
        case .greet:
            start(.sit, at: now)
        default:
            if elapsed(at: now) >= length { start(pickNext(), at: now) }
        }
        return activity
    }

    private mutating func start(_ next: CompanionActivity, at now: Date) {
        activity = next
        since = now
        length = nextLength(for: next)
    }

    /// Mostly sitting about, with play and pacing in between; never the same lively thing twice running.
    private mutating func pickNext() -> CompanionActivity {
        let choices: [(CompanionActivity, Int)] = [(.sit, 35), (.wag, 10), (.play, 20), (.walk, 20), (.climb, 15)]
        let options = choices.filter { $0.0 == .sit || $0.0 != activity }
        var roll = Int(random() % UInt64(options.reduce(0) { $0 + $1.1 }))
        for (choice, weight) in options {
            if roll < weight { return choice }
            roll -= weight
        }
        return .sit
    }

    private mutating func nextLength(for activity: CompanionActivity) -> TimeInterval {
        let range: ClosedRange<Double> = switch activity {
        case .sit: 8...16
        case .wag: 4...6
        case .play: 8...12
        case .walk: (2 * Self.walkLoop)...(2 * Self.walkLoop)
        case .wake: Self.wakeLength...Self.wakeLength
        case .climb: Self.climbLength...Self.climbLength
        case .sleep, .greet: .infinity ... .infinity
        }
        guard range.upperBound.isFinite else { return .infinity }
        if activity == .walk { return random() % 2 == 0 ? 2 * Self.walkLoop : 3 * Self.walkLoop }
        let unit = Double(random() % 1000) / 1000
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }

    /// SplitMix64, so a seeded brain is repeatable in tests.
    private mutating func random() -> UInt64 {
        seed &+= 0x9E37_79B9_7F4A_7C15
        var z = seed
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
