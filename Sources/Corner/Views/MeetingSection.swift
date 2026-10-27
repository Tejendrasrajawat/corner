import AppKit
import CornerKit
import SwiftUI

/// The card's calendar block: the meeting in progress (if any) and the next one.
struct MeetingSection: View {
    @ObservedObject var store: Store
    let ui: UIModel
    let now: Date
    @Environment(\.theme) private var theme

    var body: some View {
        let s = store.state
        VStack(alignment: .leading, spacing: 9) {
            switch store.calendarAccess {
            case .notDetermined:
                prompt("Show your next meeting", button: "Connect") { ui.connectCalendar() }
            case .denied:
                prompt("No calendar access", button: "Settings") { CalendarSource.openPrivacySettings() }
            case .granted:
                let current = s.currentMeeting(at: now)
                let next = s.upcomingMeeting(at: now)
                if current == nil && next == nil {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar").frame(width: 16)
                        Text("No meetings in the next day")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                ForEach([current, next].compactMap { $0 }) { m in
                    MeetingRow(meeting: m, now: now, alerting: s.isAlerting(m, at: now),
                               pinned: s.pinned == .meeting, store: store)
                }
            }
        }
    }

    private func prompt(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar").foregroundStyle(theme.isPlain ? Color.secondary : theme.meeting).frame(width: 16)
            Text(text).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 6)
            Chip(title: button, action: action)
        }
        .font(.system(size: 13))
    }
}

struct MeetingRow: View {
    let meeting: Meeting
    let now: Date
    let alerting: Bool
    let pinned: Bool
    let store: Store
    @Environment(\.theme) private var theme

    var body: some View {
        let m = meeting
        let started = m.start <= now
        let (text, color): (String, Color) =
            if alerting { (Format.ago(now.timeIntervalSince(m.start)), .red) }
            else if started { ("ends in \(Format.countdownShort(m.end.timeIntervalSince(now)))", .secondary) }
            else { (Format.countdownLong(m.start.timeIntervalSince(now)),
                    m.start.timeIntervalSince(now) < AppState.soonThreshold ? .orange : .secondary) }
        let times = Format.timeRange(m.start, m.end, in: .current, style: store.state.settings.clockStyle)
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(Color(hex: m.colorHex) ?? theme.meeting)
                .frame(width: 8, height: 8)
                .frame(width: 16, height: 17)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(m.title).lineLimit(1)
                    if pinned {
                        Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                Text(started ? "\(times) · now" : (isToday(m.start) ? times : "Tomorrow \(times)"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                Text(text)
                    .font(.system(size: 13, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                if let url = m.joinURL {
                    Chip(title: "Join") { NSWorkspace.shared.open(url) }
                }
            }
        }
        .font(.system(size: 13))
        .contentShape(Rectangle())
        .contextMenu {
            Button(pinned ? "Unpin from corner" : "Pin next meeting to corner") { store.togglePin(.meeting) }
            if let url = m.joinURL {
                Button("Join call") { NSWorkspace.shared.open(url) }
            }
            Button("Open Calendar") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
            }
        }
        .help(m.calendarTitle.isEmpty ? "Right-click to pin" : "\(m.calendarTitle). Right-click to pin.")
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: now)
    }
}

extension Color {
    /// "#RRGGBB".
    init?(hex: String?) {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let v = Int(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
