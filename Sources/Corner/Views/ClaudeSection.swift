import CornerKit
import SwiftUI

/// The card's Claude Code block: one row per session, waiting-on-you first.
struct ClaudeSection: View {
    @ObservedObject var store: Store
    @ObservedObject var ui: UIModel
    let now: Date

    var body: some View {
        let sessions = store.state.claudeCardSessions
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").foregroundStyle(Color.claude).frame(width: 16)
                Text("Claude").fontWeight(.medium)
                Text("· \(sessions.count) session\(sessions.count == 1 ? "" : "s")").foregroundStyle(.secondary)
                Spacer()
                if sessions.contains(where: { $0.status == .done }) {
                    Chip(title: "Clear done") { store.clearDoneClaude() }
                }
            }
            .font(.system(size: 13))
            .padding(.bottom, 4)
            ForEach(sessions) { s in
                ClaudeRow(session: s, now: now, pinned: store.state.pinned == .claude(s.id), store: store, ui: ui)
            }
        }
    }
}

struct ClaudeRow: View {
    let session: ClaudeSession
    let now: Date
    let pinned: Bool
    let store: Store
    let ui: UIModel

    var body: some View {
        let s = session
        let canOpen = ClaudeBridge.claudeAppURL != nil
        let color: Color = switch s.status {
        case .working: .claude
        case .needsYou: .orange
        case .done: .green
        }
        let subtitle: String = switch s.status {
        case .working: s.prompt.map { "“\($0)”" } ?? "Working"
        case .needsYou: s.waitingFor
        case .done: s.reply ?? "Finished after \(Format.countdownLong(s.elapsed(at: now)))"
        }
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                // Working sessions breathe, one beat per tick.
                .opacity(s.status == .working && Int(now.timeIntervalSince1970) % 2 == 1 ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.9), value: Int(now.timeIntervalSince1970) % 2)
                .frame(width: 16, height: 17)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(s.name).fontWeight(.medium).lineLimit(1)
                    if pinned {
                        Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    if s.subagentsDone > 0 {
                        Text("· \(s.subagentsDone) agent\(s.subagentsDone == 1 ? "" : "s") done")
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                Text(statusText).font(.system(size: 12)).foregroundStyle(color)
                if s.status == .needsYou && canOpen {
                    Chip(title: "Open") { open() }
                } else {
                    Text(timeText)
                        .font(.system(size: 11, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.system(size: 13))
        .padding(.vertical, 7)
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5) }
        .contentShape(Rectangle())
        .onTapGesture { if canOpen { open() } }
        .contextMenu {
            if canOpen {
                Button("Open chat in Claude") { open() }
            }
            Button("Show \(s.project) in Finder") { ClaudeBridge.showFolder(s.cwd) }
            Button(pinned ? "Unpin from corner" : "Pin to corner") { store.togglePin(.claude(s.id)) }
            Divider()
            Button("Dismiss") { store.dismissClaude(s.id) }
        }
        .help(canOpen ? "\(s.cwd)\nClick to open this chat in Claude." : s.cwd)
    }

    private func open() {
        ClaudeBridge.openChat(session)
        ui.collapse()
    }

    private var statusText: String {
        switch session.status {
        case .working: "Working"
        case .needsYou: "Needs you"
        case .done: "Done"
        }
    }

    private var timeText: String {
        switch session.status {
        case .working, .needsYou: Format.hms(Int(session.elapsed(at: now)))
        case .done: Format.ago(now.timeIntervalSince(session.finishedAt ?? now))
        }
    }
}
