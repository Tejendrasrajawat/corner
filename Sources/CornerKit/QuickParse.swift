import Foundation

public enum ParsedEntry: Equatable, Sendable {
    case timer(label: String, duration: TimeInterval)
    case countdown(label: String, target: Date, repeatRule: RepeatRule)
    case stopwatch
    case todo(String)
}

public enum ParseError: Error, Equatable, Sendable {
    case notUnderstood
    case inThePast

    public var message: String {
        switch self {
        case .notUnderstood: "Couldn't read that date. Try fri 6pm release or 24 dec party."
        case .inThePast: "That time has already passed."
        }
    }
}

/// Reads the quick-add box. A duration makes a timer ("25m focus", "1h30", "in 2h deploy");
/// a time or date makes a countdown ("until 6pm", "fri 6pm release freeze", "24 dec party");
/// "daily", "weekdays" or "every fri" make it repeat; "sw" starts the stopwatch.
/// Whatever is left over becomes the label. Text with no time in it at all becomes a to-do,
/// and a "todo", "note" or "-" prefix forces one ("todo 5 things to fix" isn't a 5-minute timer).
public enum QuickParse {
    enum Day: Equatable {
        case today, tomorrow
        case weekday(Int)
        case date(year: Int?, month: Int, day: Int)
    }

    typealias TimeOfDay = (hour: Int, minute: Int)

    public static func parse(_ text: String, now: Date, calendar: Calendar = .current) -> Result<ParsedEntry, ParseError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        let lower = words.map { $0.lowercased() }
        guard !words.isEmpty else { return .failure(.notUnderstood) }
        if words.count == 1, ["sw", "stopwatch"].contains(lower[0]) { return .success(.stopwatch) }
        for prefix in todoPrefixes where trimmed.lowercased().hasPrefix(prefix) {
            let rest = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty { return .success(.todo(rest)) }
        }

        var duration: TimeInterval = 0
        var time: TimeOfDay?
        var day: Day?
        var rule = RepeatRule.none
        var label: [String] = []
        var i = 0

        func word(_ offset: Int) -> String? { i + offset < lower.count ? lower[i + offset] : nil }
        func nothingYet() -> Bool { label.isEmpty && duration == 0 && time == nil && day == nil && rule == .none }

        while i < lower.count {
            let w = lower[i]
            // "at", "until", "in"… only count as filler when a time or duration follows, so
            // "sign up to gym" keeps its "to".
            if fillers.contains(w), let next = word(1), isTemporal(next, then: word(2)) { i += 1; continue }
            switch w {
            case "daily", "everyday": rule = .daily; i += 1; continue
            case "weekly": rule = .weekly; i += 1; continue
            case "weekdays": rule = .weekdays; i += 1; continue
            case "today": day = .today; i += 1; continue
            case "tomorrow", "tmrw", "tmr": day = .tomorrow; i += 1; continue
            default: break
            }
            if w == "every", let next = word(1) {
                if next == "day" { rule = .daily; i += 2; continue }
                if next == "weekday" || next == "weekdays" { rule = .weekdays; i += 2; continue }
                if next == "week" { rule = .weekly; i += 2; continue }
                if let wd = weekdays[next] { rule = .weekly; day = .weekday(wd); i += 2; continue }
            }
            if w == "next" || w == "this", let next = word(1), let wd = weekdays[next] {
                day = .weekday(wd); i += 2; continue
            }
            if let wd = weekdays[w] { day = .weekday(wd); i += 1; continue }
            if let t = timeOfDay(w, then: word(1)) { time = t.time; i += t.used; continue }
            if let d = date(w, then: word(1)) { day = d.day; i += d.used; continue }
            if let d = compactDuration(w) { duration += d; i += 1; continue }
            if let n = Double(w), let unit = word(1).flatMap({ units[$0] }) { duration += n * unit; i += 2; continue }
            // A bare number up front is minutes: "45", "5 tea".
            if nothingYet(), let n = Int(w), (1...999).contains(n) { duration += Double(n) * 60; i += 1; continue }
            label.append(words[i])
            i += 1
        }

        let joined = label.joined(separator: " ")
        let name: String? = joined.isEmpty ? nil : joined.prefix(1).uppercased() + joined.dropFirst()

        if time == nil && day == nil && rule == .none {
            guard duration > 0 else { return .success(.todo(trimmed)) }
            return .success(.timer(label: name ?? "Timer", duration: duration))
        }
        // "finish report today" is a to-do; a countdown to the start of today would already be over.
        if day == .today && time == nil && rule == .none { return .success(.todo(trimmed)) }
        return resolve(time: time, day: day, rule: rule, now: now, calendar: calendar)
            .map { .countdown(label: name ?? "Countdown", target: $0, repeatRule: rule) }
    }

    /// The preview line under the quick-add box.
    public static func describe(_ entry: ParsedEntry, now: Date, calendar: Calendar = .current, style: ClockStyle = .h24) -> String {
        switch entry {
        case .stopwatch:
            return "Starts the stopwatch"
        case .todo(let text):
            return "To-do · \(text)"
        case let .timer(label, duration):
            return "\(Format.durationWords(duration)) timer · \(label)"
        case let .countdown(label, target, rule):
            let time = Format.time(target, in: calendar.timeZone, style: style)
            switch rule {
            case .daily: return "Every day at \(time) · \(label)"
            case .weekdays: return "Every weekday at \(time) · \(label)"
            case .weekly: return "Every \(weekdayName(target, calendar)) at \(time) · \(label)"
            case .none: return "Countdown to \(dayPhrase(target, now: now, calendar: calendar)), \(time) · \(label)"
            }
        }
    }

    /// An SF Symbol picked from words in the label.
    public static func icon(for label: String) -> String {
        let l = label.lowercased()
        let table: [(symbol: String, words: [String])] = [
            ("person.2", ["standup", "stand-up", "meeting", "call", "sync", "1:1", "interview", "demo", "retro", "planning"]),
            ("paperplane", ["release", "deploy", "launch", "ship", "freeze", "rollout"]),
            ("sun.max", ["weekend", "holiday", "vacation", "leave", "diwali"]),
            ("fork.knife", ["lunch", "dinner", "breakfast", "food"]),
            ("gift", ["birthday", "party", "anniversary"]),
            ("airplane", ["flight", "travel", "train", "trip"]),
            ("chart.bar", ["tracker", "report", "review"]),
        ]
        return table.first { entry in entry.words.contains { l.contains($0) } }?.symbol ?? "calendar"
    }

    // MARK: - Resolving a target date

    static func resolve(time: TimeOfDay?, day: Day?, rule: RepeatRule, now: Date, calendar cal: Calendar) -> Result<Date, ParseError> {
        // A bare date means its start; a repeat with no time means 09:00.
        let (h, m) = time ?? (rule == .none ? (0, 0) : (9, 0))
        let today = cal.startOfDay(for: now)
        func at(_ offset: Int) -> Date {
            let d = cal.date(byAdding: .day, value: offset, to: today)!
            return cal.date(bySettingHour: h, minute: m, second: 0, of: d)!
        }

        switch day {
        case nil:
            var d = at(0)
            if d <= now { d = at(1) }
            if rule == .weekdays {
                while Recurrence.isWeekend(d, calendar: cal) { d = cal.date(byAdding: .day, value: 1, to: d)! }
            }
            return .success(d)
        case .today:
            let d = at(0)
            return d > now ? .success(d) : .failure(.inThePast)
        case .tomorrow:
            return .success(at(1))
        case .weekday(let wd):
            for offset in 0...7 {
                let d = at(offset)
                if cal.component(.weekday, from: d) == wd && d > now { return .success(d) }
            }
            return .failure(.notUnderstood)
        case let .date(year, month, dayOfMonth):
            var comps = DateComponents(year: year ?? cal.component(.year, from: now), month: month, day: dayOfMonth, hour: h, minute: m)
            // Calendar quietly turns 31 Feb into 3 Mar; reject that.
            guard let d = cal.date(from: comps), cal.component(.day, from: d) == dayOfMonth else { return .failure(.notUnderstood) }
            if d > now { return .success(d) }
            guard year == nil else { return .failure(.inThePast) }
            comps.year = (comps.year ?? 0) + 1
            return cal.date(from: comps).map { .success($0) } ?? .failure(.notUnderstood)
        }
    }

    // MARK: - Tokens

    static let todoPrefixes = ["todo:", "todo ", "note:", "note ", "- ", "* ", "[ ] ", "[] "]

    static let fillers: Set<String> = ["until", "till", "til", "at", "on", "by", "in", "for", "to"]

    static let keywords: Set<String> = ["today", "tomorrow", "tmrw", "tmr", "noon", "midnight", "every", "daily", "everyday", "weekly", "weekdays"]

    static let units: [String: TimeInterval] = [
        "s": 1, "sec": 1, "secs": 1, "second": 1, "seconds": 1,
        "m": 60, "min": 60, "mins": 60, "minute": 60, "minutes": 60,
        "h": 3600, "hr": 3600, "hrs": 3600, "hour": 3600, "hours": 3600,
    ]

    /// Calendar weekday numbers: 1 is Sunday.
    static let weekdays: [String: Int] = [
        "sun": 1, "sunday": 1, "mon": 2, "monday": 2,
        "tue": 3, "tues": 3, "tuesday": 3, "wed": 4, "weds": 4, "wednesday": 4,
        "thu": 5, "thur": 5, "thurs": 5, "thursday": 5, "fri": 6, "friday": 6,
        "sat": 7, "saturday": 7,
    ]

    static let months: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3,
        "apr": 4, "april": 4, "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7,
        "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10,
        "nov": 11, "november": 11, "dec": 12, "december": 12,
    ]

    static func isTemporal(_ w: String, then next: String?) -> Bool {
        keywords.contains(w) || weekdays[w] != nil || timeOfDay(w, then: next) != nil
            || date(w, then: next) != nil || compactDuration(w) != nil || Double(w) != nil
    }

    /// "6pm", "6:30pm", "6 pm", "18:00", "18.30", "noon", "midnight". A bare "6" is not a time.
    static func timeOfDay(_ w: String, then next: String?) -> (time: TimeOfDay, used: Int)? {
        if w == "noon" { return ((12, 0), 1) }
        if w == "midnight" { return ((0, 0), 1) }
        guard let m = w.wholeMatch(of: #/(\d{1,2})(?:[:.](\d{2}))?(am|pm|a|p)?/#), let hour = Int(m.1) else { return nil }
        let minute = m.2.flatMap { Int($0) } ?? 0
        guard minute < 60 else { return nil }
        var suffix = m.3.map(String.init)
        var used = 1
        if suffix == nil, let n = next, ["am", "pm", "a.m.", "p.m."].contains(n) {
            suffix = String(n.prefix(1))
            used = 2
        }
        if let s = suffix {
            guard (1...12).contains(hour) else { return nil }
            return ((hour % 12 + (s.hasPrefix("p") ? 12 : 0), minute), used)
        }
        guard m.2 != nil, hour < 24 else { return nil }
        return ((hour, minute), 1)
    }

    /// "2026-10-24", "24/10" (day first), "24/10/26", "24 oct", "oct 24", "24th dec".
    static func date(_ w: String, then next: String?) -> (day: Day, used: Int)? {
        if let m = w.wholeMatch(of: #/(\d{4})-(\d{1,2})-(\d{1,2})/#), let y = Int(m.1), let mo = Int(m.2), let d = Int(m.3) {
            return (.date(year: y, month: mo, day: d), 1)
        }
        if let m = w.wholeMatch(of: #/(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?/#), let d = Int(m.1), let mo = Int(m.2) {
            guard (1...12).contains(mo), (1...31).contains(d) else { return nil }
            let year = m.3.flatMap { Int($0) }.map { $0 < 100 ? 2000 + $0 : $0 }
            return (.date(year: year, month: mo, day: d), 1)
        }
        guard let n = next else { return nil }
        if let d = dayNumber(w), let mo = months[n] { return (.date(year: nil, month: mo, day: d), 2) }
        if let mo = months[w], let d = dayNumber(n) { return (.date(year: nil, month: mo, day: d), 2) }
        return nil
    }

    static func dayNumber(_ w: String) -> Int? {
        var s = Substring(w)
        for suffix in ["st", "nd", "rd", "th"] where s.hasSuffix(suffix) { s = s.dropLast(2) }
        guard let d = Int(s), (1...31).contains(d) else { return nil }
        return d
    }

    /// "25m", "90s", "1.5h", "25min", "1h30m", "1h30" (30 minutes), "2m30" (30 seconds).
    static func compactDuration(_ w: String) -> TimeInterval? {
        var total: TimeInterval = 0
        var rest = Substring(w)
        var lastUnit: TimeInterval?
        while !rest.isEmpty {
            let number = rest.prefix { $0.isNumber || $0 == "." }
            guard !number.isEmpty, let value = Double(number) else { return nil }
            rest = rest.dropFirst(number.count)
            let unitText = rest.prefix { $0.isLetter }
            rest = rest.dropFirst(unitText.count)
            if unitText.isEmpty {
                guard rest.isEmpty, let last = lastUnit, last > 1 else { return nil }
                return total + value * last / 60
            }
            guard let unit = units[String(unitText)] else { return nil }
            total += value * unit
            lastUnit = unit
        }
        return total > 0 ? total : nil
    }

    static func dayPhrase(_ target: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(target, inSameDayAs: now) { return "today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(target, inSameDayAs: tomorrow) {
            return "tomorrow"
        }
        return Format.shortDate(target, in: calendar.timeZone)
    }

    static func weekdayName(_ date: Date, _ calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = calendar.timeZone
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }
}
