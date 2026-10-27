import CornerKit
import SwiftUI

/// The expanded widget.
struct CardView: View {
    @ObservedObject var store: Store
    @ObservedObject var ui: UIModel
    @Environment(\.theme) private var theme

    var body: some View {
        let s = store.state
        let now = store.now
        VStack(alignment: .leading, spacing: 0) {
            header(s, now)
            if ui.quickAddActive {
                QuickAddField(store: store, ui: ui)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
            if s.settings.showClaude && !s.claudeSessions.isEmpty {
                divider
                ClaudeSection(store: store, ui: ui, now: now).padding(12)
            }
            divider
            timers(s, now).padding(12)
            if s.settings.showMeetings {
                divider
                MeetingSection(store: store, ui: ui, now: now).padding(12)
            }
            if !s.countdowns.isEmpty {
                divider
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(s.countdowns) { c in
                        CountdownRow(countdown: c, now: now, pinned: s.pinned == .countdown(c.id), store: store)
                    }
                }
                .padding(12)
            }
            divider
            TodoSection(store: store, ui: ui).padding(12)
            divider
            stopwatch(s, now).padding(12)
            divider
            workday(s, now).padding(12)
            divider
            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
        }
        .frame(width: 280)
        .background(ThemedBackground(kind: .card))
        .overlay(
            UnevenRoundedRectangle(bottomTrailingRadius: Masks.cardRadius)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 0.5)
    }

    private func header(_ s: AppState, _ now: Date) -> some View {
        let main = s.settings.primaryZone
        let style = s.settings.clockStyle
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                (Text(Format.clock(now, in: main.timeZone, seconds: true, style: style))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    + Text(style == .h12 ? " \(Format.period(now, in: main.timeZone))" : "")
                    .font(.system(size: 13, weight: .semibold, design: .rounded)))
                    .monospacedDigit()
                Text("\(main.label) · \(Format.shortDate(now, in: main.timeZone))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            ForEach(s.settings.secondaryZones, id: \.self) { zone in
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Format.time(now, in: zone.timeZone, style: style))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(zone.label)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            IconButton(symbol: "arrow.up.left", help: "Minimize to corner") { ui.collapse() }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func timers(_ s: AppState, _ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(s.timers) { t in
                TimerBlock(timer: t, now: now, pinned: s.pinned == .timer(t.id), store: store)
            }
            HStack(spacing: 6) {
                Text("New timer")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                Spacer()
                ForEach([5, 15, 25, 45], id: \.self) { minutes in
                    Chip(title: "\(minutes)m") { store.startTimer(minutes: minutes) }
                }
            }
        }
    }

    private func stopwatch(_ s: AppState, _ now: Date) -> some View {
        let sw = s.stopwatch
        let laps = Array(Array(sw.laps.enumerated()).suffix(3).reversed())
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "stopwatch").foregroundStyle(theme.stopwatch).frame(width: 16)
                Text("Stopwatch")
                Spacer()
                Text(Format.stopwatch(sw.elapsed(at: now)))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(sw.isRunning ? Color.primary : Color.secondary)
                IconButton(symbol: sw.isRunning ? "pause.fill" : "play.fill",
                           help: sw.isRunning ? "Pause stopwatch" : "Start stopwatch") { store.toggleStopwatch() }
                if sw.isRunning {
                    IconButton(symbol: "flag", help: "Lap") { store.lap() }
                } else if sw.isActive {
                    IconButton(symbol: "arrow.counterclockwise", help: "Reset stopwatch") { store.resetStopwatch() }
                }
            }
            .font(.system(size: 13))
            ForEach(laps, id: \.offset) { index, total in
                HStack {
                    Text("Lap \(index + 1)")
                    Spacer()
                    Text(Format.stopwatch(total - (index > 0 ? sw.laps[index - 1] : 0))).monospacedDigit()
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 22)
            }
        }
    }

    private func workday(_ s: AppState, _ now: Date) -> some View {
        let p = s.workdayProgress(at: now)
        let start = Format.minutesOfDay(s.settings.workdayStartMinutes, style: s.settings.clockStyle)
        let end = Format.minutesOfDay(s.settings.workdayEndMinutes, style: s.settings.clockStyle)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Workday \(start) to \(end)")
                Spacer()
                Text("\(Int((p * 100).rounded()))%").monospacedDigit()
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            Bar(value: p, tint: theme.workday)
        }
    }

    private var footer: some View {
        HStack {
            Button { ui.startQuickAdd() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Add")
                    Text("⌥⌘T").foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            Button { ui.openSettings() } label: {
                Image(systemName: "gearshape").contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
}

struct TimerBlock: View {
    let timer: CTimer
    let now: Date
    let pinned: Bool
    let store: Store
    @Environment(\.theme) private var theme

    var body: some View {
        let r = timer.remaining(at: now)
        let over = r <= 0
        let alert = over && timer.isRunning
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "hourglass").foregroundStyle(alert ? Color.red : theme.timer)
                Text(timer.label).fontWeight(.medium).lineLimit(1)
                if pinned {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(over ? "over" : "of \(Format.hms(Int(timer.duration)))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            Text(over ? Format.overtime(-r) : Format.remaining(r))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(alert ? Color.red : (timer.isRunning ? Color.primary : Color.secondary))
            Bar(value: timer.progress(at: now), tint: alert ? .red : theme.timer)
            HStack(spacing: 6) {
                IconButton(symbol: timer.isRunning ? "pause.fill" : "play.fill",
                           help: timer.isRunning ? "Pause" : "Start") { store.toggleTimer(timer.id) }
                IconButton(symbol: "arrow.counterclockwise", help: "Reset") { store.resetTimer(timer.id) }
                Chip(title: "+5 min") { store.extendTimer(timer.id, by: 300) }
                Spacer()
                IconButton(symbol: pinned ? "pin.slash" : "pin",
                           help: pinned ? "Unpin from corner" : "Pin to corner") { store.togglePin(.timer(timer.id)) }
                IconButton(symbol: "xmark", help: "Remove timer") { store.removeTimer(timer.id) }
            }
            .padding(.top, 4)
        }
    }
}

struct CountdownRow: View {
    let countdown: Countdown
    let now: Date
    let pinned: Bool
    let store: Store
    @Environment(\.theme) private var theme

    var body: some View {
        let c = countdown
        let r = c.remaining(at: now)
        let (text, color): (String, Color) =
            if c.isAlerting(at: now) { (Format.ago(now.timeIntervalSince(c.firedAt ?? now)), .red) }
            else if r <= 0 { ("done", .secondary) }
            else { (Format.countdownLong(r), r < AppState.soonThreshold ? .orange : .secondary) }
        HStack(spacing: 6) {
            Image(systemName: c.icon).foregroundStyle(theme.countdown).frame(width: 16)
            Text(c.label).lineLimit(1)
            if c.repeatRule != .none {
                Image(systemName: "repeat").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            if pinned {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Text(text)
                .font(.system(size: 13, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            let close = CountdownClose(c, at: now, style: store.state.settings.clockStyle)
            Button { store.closeCountdown(c.id) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(close.help)
            .accessibilityLabel(close.title)
        }
        .font(.system(size: 13))
        .contentShape(Rectangle())
        .contextMenu {
            Button(pinned ? "Unpin from corner" : "Pin to corner") { store.togglePin(.countdown(c.id)) }
            Button(CountdownClose(c, at: now, style: store.state.settings.clockStyle).title) { store.closeCountdown(c.id) }
            if c.repeatRule != .none {
                Button("Remove for good", role: .destructive) { store.removeCountdown(c.id) }
            }
        }
        .help("\(Format.shortDate(c.target, in: .current)), \(Format.time(c.target, in: .current, style: store.state.settings.clockStyle)). Right-click to pin.")
    }
}

/// What closing a countdown early does, for its × button and menus. A one-off closes; a repeating
/// one skips to its next occurrence, or stops alerting while it's going off.
struct CountdownClose {
    let title: String
    let help: String

    init(_ c: Countdown, at now: Date, style: ClockStyle) {
        if c.repeatRule == .none {
            title = c.remaining(at: now) > 0 ? "Close now" : "Close"
            help = c.remaining(at: now) > 0 ? "Close \(c.label) now, before it's due." : "Close \(c.label)."
        } else if c.isAlerting(at: now) {
            title = "Dismiss"
            help = "Stop the alert. \(c.label) carries on with its next one."
        } else if let next = c.occurrenceAfterTarget() {
            title = "Skip this one"
            help = "Skip this \(c.label); the next is \(Format.shortDate(next, in: .current)), \(Format.time(next, in: .current, style: style))."
        } else {
            title = "Close now"
            help = "Close \(c.label) now."
        }
    }
}
