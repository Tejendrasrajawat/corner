import Foundation

public enum Format {
    /// Digits only: "14:32" or, 12-hour, "2:32". Pair with `period` where AM/PM goes elsewhere.
    public static func clock(_ date: Date, in zone: TimeZone, seconds: Bool, style: ClockStyle = .h24) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        let hour = c.hour ?? 0
        let hm = style == .h12
            ? String(format: "%d:%02d", hour % 12 == 0 ? 12 : hour % 12, c.minute ?? 0)
            : String(format: "%02d:%02d", hour, c.minute ?? 0)
        return seconds ? hm + String(format: ":%02d", c.second ?? 0) : hm
    }

    public static func period(_ date: Date, in zone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.component(.hour, from: date) < 12 ? "AM" : "PM"
    }

    /// A time on its own: "18:00" or "6:00 PM".
    public static func time(_ date: Date, in zone: TimeZone, style: ClockStyle) -> String {
        let digits = clock(date, in: zone, seconds: false, style: style)
        return style == .h12 ? "\(digits) \(period(date, in: zone))" : digits
    }

    /// "19:48–20:18", or "7:48–8:18 PM", with AM/PM on both ends only when it changes.
    public static func timeRange(_ start: Date, _ end: Date, in zone: TimeZone, style: ClockStyle) -> String {
        guard style == .h12, period(start, in: zone) == period(end, in: zone) else {
            return "\(time(start, in: zone, style: style))–\(time(end, in: zone, style: style))"
        }
        return "\(clock(start, in: zone, seconds: false, style: .h12))–\(time(end, in: zone, style: .h12))"
    }

    /// "18:42", or "1:05:12" from an hour up.
    public static func hms(_ total: Int) -> String {
        let t = max(0, total)
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// Rounds up, so a timer reads 00:00 exactly when it ends.
    public static func remaining(_ seconds: TimeInterval) -> String {
        hms(Int(seconds.rounded(.up)))
    }

    public static func overtime(_ seconds: TimeInterval) -> String {
        "+" + hms(Int(seconds.rounded(.down)))
    }

    /// Always "00:12:08", so the stopwatch row doesn't jump width.
    public static func stopwatch(_ seconds: TimeInterval) -> String {
        let t = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }

    /// For the corner: "2d 4h", "4h 12m", "11m", "45s".
    public static func countdownShort(_ seconds: TimeInterval) -> String {
        let t = Int(seconds)
        let d = t / 86400, h = (t % 86400) / 3600, m = (t % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(max(0, Int(seconds.rounded(.up))))s"
    }

    /// For the card: "2d 03h 28m", "4h 12m", "11m 20s", "45s".
    public static func countdownLong(_ seconds: TimeInterval) -> String {
        let t = Int(seconds)
        let d = t / 86400, h = (t % 86400) / 3600, m = (t % 3600) / 60, s = t % 60
        if d > 0 { return String(format: "%dd %02dh %02dm", d, h, m) }
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        if m > 0 { return String(format: "%dm %02ds", m, s) }
        return "\(max(0, Int(seconds.rounded(.up))))s"
    }

    public static func ago(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "now" : "\(countdownShort(seconds)) ago"
    }

    /// "25 min", "1 h 30 min", "90 s" → "1 min 30 s".
    public static func durationWords(_ seconds: TimeInterval) -> String {
        let t = Int(seconds.rounded())
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) h") }
        if m > 0 { parts.append("\(m) min") }
        if s > 0 { parts.append("\(s) s") }
        return parts.isEmpty ? "0 s" : parts.joined(separator: " ")
    }

    /// "Wed 21 Oct".
    public static func shortDate(_ date: Date, in zone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = zone
        f.dateFormat = "EEE d MMM"
        return f.string(from: date)
    }

    /// Minutes after midnight: "19:00" or "7:00 PM".
    public static func minutesOfDay(_ minutes: Int, style: ClockStyle = .h24) -> String {
        let h = (minutes / 60) % 24, m = minutes % 60
        guard style == .h12 else { return String(format: "%02d:%02d", h, m) }
        return String(format: "%d:%02d", h % 12 == 0 ? 12 : h % 12, m) + (h < 12 ? " AM" : " PM")
    }
}
