import Foundation

public enum ClaudeStatus: String, Codable, Sendable {
    case working, needsYou, done
}

/// One Claude Code session, as seen through its hooks.
public struct ClaudeSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var cwd: String
    /// The start of the last prompt you sent, so sessions can be told apart.
    public var prompt: String?
    /// What Claude is waiting on, from its notification ("Claude needs your permission to use Bash").
    public var detail: String?
    /// The start of Claude's final message when it finished.
    public var reply: String?
    public var status: ClaudeStatus
    /// When the current turn began.
    public var startedAt: Date
    public var updatedAt: Date
    public var finishedAt: Date?
    /// You've opened the card since it last needed you or finished.
    public var seen: Bool
    public var subagentsDone: Int
    /// The Claude desktop chat running this session, and its title there. Nil for a session
    /// started in Terminal, or until Corner has found the chat.
    public var chatID: String?
    public var title: String?

    public init(id: String, cwd: String, status: ClaudeStatus, at now: Date) {
        self.id = id
        self.cwd = cwd
        self.status = status
        self.startedAt = now
        self.updatedAt = now
        self.seen = false
        self.subagentsDone = 0
    }

    /// The folder Claude is working in, e.g. "Media".
    public var project: String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? "Claude" : name
    }

    /// What to call the session: its chat's title in Claude desktop, else its folder.
    public var name: String {
        guard let title, !title.isEmpty else { return project }
        return title
    }

    public func elapsed(at now: Date) -> TimeInterval {
        max(0, (finishedAt ?? now).timeIntervalSince(startedAt))
    }

    /// The notification, shortened to fit a row: "Claude needs your permission to use Bash" → "Permission for Bash".
    public var waitingFor: String {
        guard let detail, !detail.isEmpty else { return "Waiting for you" }
        let permission = "Claude needs your permission to use "
        if detail.hasPrefix(permission) { return "Permission for " + detail.dropFirst(permission.count) }
        if detail.localizedCaseInsensitiveContains("waiting for your input") { return "Waiting for your reply" }
        return detail
    }
}

/// One line of the hook inbox: the JSON Claude Code hands a hook on stdin.
public struct ClaudeEvent: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case promptSubmitted = "UserPromptSubmit"
        case toolFinished = "PostToolUse"
        case notification = "Notification"
        case stopped = "Stop"
        case subagentStopped = "SubagentStop"
        case sessionEnded = "SessionEnd"
    }

    public var kind: Kind
    public var sessionID: String
    public var cwd: String
    public var prompt: String?
    public var message: String?
    public var notificationType: String?
    /// Stop's `last_assistant_message`.
    public var lastMessage: String?

    public init(kind: Kind, sessionID: String, cwd: String = "", prompt: String? = nil, message: String? = nil,
                notificationType: String? = nil, lastMessage: String? = nil) {
        self.kind = kind
        self.sessionID = sessionID
        self.cwd = cwd
        self.prompt = prompt
        self.message = message
        self.notificationType = notificationType
        self.lastMessage = lastMessage
    }

    /// An inbox line is "<unix seconds> <hook JSON>", written by the hook script. The time lets
    /// Corner order events correctly and skip alerts for ones it reads late.
    public static func parseInboxLine(_ line: String) -> (time: Date?, event: ClaudeEvent)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let space = trimmed.firstIndex(of: " "), let seconds = TimeInterval(trimmed[..<space]),
           let event = parse(String(trimmed[trimmed.index(after: space)...])) {
            return (Date(timeIntervalSince1970: seconds), event)
        }
        return parse(trimmed).map { (nil, $0) }
    }

    /// Nil for blank lines, broken JSON, or events Corner doesn't use.
    public static func parse(_ line: String) -> ClaudeEvent? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["hook_event_name"] as? String,
              let kind = Kind(rawValue: name),
              let id = object["session_id"] as? String, !id.isEmpty else { return nil }
        return ClaudeEvent(kind: kind, sessionID: id, cwd: object["cwd"] as? String ?? "",
                           prompt: object["prompt"] as? String, message: object["message"] as? String,
                           notificationType: object["notification_type"] as? String,
                           lastMessage: object["last_assistant_message"] as? String)
    }
}

extension AppState {
    /// A turn shorter than this finishes quietly: you were probably watching it.
    public static let claudeNotifyAfter: TimeInterval = 30
    /// How long a finished session stays in the card.
    public static let claudeDoneLifetime: TimeInterval = 30 * 60
    /// How long a finished session can take over the corner if you haven't looked.
    public static let claudeDoneCornerWindow: TimeInterval = 10 * 60
    /// A session that goes quiet this long without a Stop (killed, crashed) is dropped.
    public static let claudeStaleAfter: TimeInterval = 12 * 3600

    /// Applies one hook event. Returns an alert when Claude needs you, or finished a turn long
    /// enough that you've probably looked away.
    public mutating func apply(_ event: ClaudeEvent, at now: Date) -> AlertEvent? {
        if event.kind == .sessionEnded {
            claudeSessions.removeAll { $0.id == event.sessionID }
            if pinned == .claude(event.sessionID) { pinned = nil }
            return nil
        }
        // Sessions that were already running when the hooks went in show up on their next event.
        let index = claudeSessions.firstIndex { $0.id == event.sessionID } ?? {
            claudeSessions.append(ClaudeSession(id: event.sessionID, cwd: event.cwd, status: .working, at: now))
            return claudeSessions.count - 1
        }()
        var s = claudeSessions[index]
        if !event.cwd.isEmpty { s.cwd = event.cwd }
        s.updatedAt = now
        var alert: AlertEvent?

        switch event.kind {
        case .promptSubmitted:
            s.status = .working
            s.startedAt = now
            s.finishedAt = nil
            s.detail = nil
            s.seen = false
            s.subagentsDone = 0
            s.prompt = event.prompt.map(Self.snippet)
            s.reply = nil
        case .toolFinished:
            // A tool ran, so whatever Claude was waiting on has been answered.
            if s.status == .needsYou {
                s.status = .working
                s.detail = nil
            }
        case .notification:
            // After a turn ends Claude Code also sends an idle "waiting for your input" reminder;
            // the session already reads as done, so that one changes nothing.
            guard s.status != .done, Self.notificationNeedsYou(event) else { break }
            let first = s.status != .needsYou
            s.status = .needsYou
            s.detail = event.message
            s.seen = false
            if first { alert = .claudeNeedsYou(s) }
        case .stopped:
            let wasActive = s.status != .done
            s.status = .done
            s.finishedAt = now
            s.detail = nil
            s.seen = false
            s.reply = event.lastMessage.map(Self.snippet).flatMap { $0.isEmpty ? nil : $0 }
            if wasActive && s.elapsed(at: now) >= Self.claudeNotifyAfter { alert = .claudeDone(s) }
        case .subagentStopped:
            s.subagentsDone += 1
        case .sessionEnded:
            break
        }
        claudeSessions[index] = s
        return alert
    }

    /// Notification types that mean Claude is blocked on you. Unknown or missing types count, so
    /// a Claude Code that doesn't send the field still works.
    static func notificationNeedsYou(_ event: ClaudeEvent) -> Bool {
        guard let type = event.notificationType else { return true }
        return ["permission_prompt", "idle_prompt", "elicitation_dialog"].contains(type)
    }

    /// First line of a prompt, whitespace collapsed, at most 80 characters.
    static func snippet(_ prompt: String) -> String {
        let firstLine = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let collapsed = firstLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > 80 ? String(collapsed.prefix(79)) + "…" : collapsed
    }

    mutating func clearOldClaudeSessions(at now: Date) {
        claudeSessions.removeAll { s in
            if s.status == .done, let finished = s.finishedAt {
                return now.timeIntervalSince(finished) > Self.claudeDoneLifetime
            }
            return now.timeIntervalSince(s.updatedAt) > Self.claudeStaleAfter
        }
        if case .claude(let id)? = pinned, !claudeSessions.contains(where: { $0.id == id }) { pinned = nil }
    }

    public mutating func clearDoneClaudeSessions() {
        claudeSessions.removeAll { $0.status == .done }
    }

    /// Records which Claude desktop chat each session belongs to, keyed by session id. Returns
    /// whether anything changed, so callers can skip saving.
    @discardableResult
    public mutating func setClaudeChats(_ chats: [String: ClaudeChat]) -> Bool {
        var changed = false
        for i in claudeSessions.indices {
            guard let chat = chats[claudeSessions[i].id] else { continue }
            if claudeSessions[i].chatID != chat.id || claudeSessions[i].title != chat.title {
                claudeSessions[i].chatID = chat.id
                claudeSessions[i].title = chat.title
                changed = true
            }
        }
        return changed
    }

    /// The card's order: waiting on you, then working (longest first), then done (latest first).
    public var claudeCardSessions: [ClaudeSession] {
        let needs = claudeSessions.filter { $0.status == .needsYou }.sorted { $0.updatedAt > $1.updatedAt }
        let working = claudeSessions.filter { $0.status == .working }.sorted { $0.startedAt < $1.startedAt }
        let done = claudeSessions.filter { $0.status == .done }.sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
        return needs + working + done
    }

    func claudeFace(for s: ClaudeSession, at now: Date) -> CornerFace {
        switch s.status {
        case .working:
            return CornerFace(ref: .claude(s.id), value: Format.hms(Int(s.elapsed(at: now))),
                              label: s.name, progress: 0.3, tone: .working, indeterminate: true)
        case .needsYou:
            return CornerFace(ref: .claude(s.id), value: Format.hms(Int(s.elapsed(at: now))),
                              label: "Needs you", progress: 1, tone: .warning)
        case .done:
            return CornerFace(ref: .claude(s.id), value: "Done",
                              label: "\(s.name) · \(Format.countdownShort(s.elapsed(at: now)))", progress: 1, tone: .success)
        }
    }

    /// Sessions the corner and menu bar may show: none while Claude activity is switched off.
    var visibleClaudeSessions: [ClaudeSession] { settings.showClaude ? claudeSessions : [] }

    /// A session asking for you, most recent first.
    func claudeNeedingYou() -> ClaudeSession? {
        visibleClaudeSessions.filter { $0.status == .needsYou }.max { $0.updatedAt < $1.updatedAt }
    }

    /// A finished session you haven't looked at yet, while it's fresh.
    func claudeFreshlyDone(at now: Date) -> ClaudeSession? {
        visibleClaudeSessions
            .filter { s in
                guard s.status == .done, !s.seen, let finished = s.finishedAt else { return false }
                return now.timeIntervalSince(finished) < Self.claudeDoneCornerWindow
            }
            .max { ($0.finishedAt ?? .distantPast) < ($1.finishedAt ?? .distantPast) }
    }

    /// The session that's been working longest.
    func claudeWorking() -> ClaudeSession? {
        visibleClaudeSessions.filter { $0.status == .working }.min { $0.startedAt < $1.startedAt }
    }
}

/// Adds and removes Corner's entries in Claude Code's settings.json, leaving everything else alone.
public enum ClaudeHooks {
    public static let events = ["UserPromptSubmit", "PostToolUse", "Notification", "Stop", "SubagentStop", "SessionEnd"]

    /// The hook itself: append one line to Corner's inbox and get out of Claude's way. The JSON
    /// arrives on stdin; newlines are stripped so it stays one line (JSON strings can't hold raw ones).
    public static let script = """
    #!/bin/sh
    # Installed by Corner (Settings → Claude Code). Claude Code runs this on each hook event; it
    # appends the event's JSON to Corner's inbox with a timestamp and exits. Nothing leaves this Mac.
    inbox="$HOME/Library/Application Support/Corner/claude-events.jsonl"
    { printf '%s ' "$(date +%s)"; tr -d '\\n'; printf '\\n'; } >> "$inbox" 2>/dev/null
    exit 0

    """
    /// Claude Code runs hook commands through a shell, so $HOME expands and the quotes keep the space.
    public static let command = "\"$HOME/Library/Application Support/Corner/claude-hook.sh\""
    static let marker = "Corner/claude-hook.sh"

    public static func isInstalled(in settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { groups(hooks[$0]).contains(where: isOurs) }
    }

    public static func adding(to settings: [String: Any]) -> [String: Any] {
        var settings = removing(from: settings)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var group: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": 5]]]
            // Tool events take a matcher; "*" is every tool.
            if event == "PostToolUse" { group["matcher"] = "*" }
            hooks[event] = groups(hooks[event]) + [group]
        }
        settings["hooks"] = hooks
        return settings
    }

    public static func removing(from settings: [String: Any]) -> [String: Any] {
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        var settings = settings
        for (event, value) in hooks {
            let kept = groups(value).filter { !isOurs($0) }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return settings
    }

    static func groups(_ value: Any?) -> [[String: Any]] {
        value as? [[String: Any]] ?? []
    }

    static func isOurs(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains(marker) == true }
    }
}

/// A chat in the Claude desktop app.
public struct ClaudeChat: Equatable, Sendable {
    /// "local_…", the id the app's links take.
    public var id: String
    public var title: String?

    public init(id: String, title: String?) {
        self.id = id
        self.title = title
    }
}

/// Reading Claude desktop's chats and linking into them. The app keeps one record per Code chat
/// (`local_<id>.json`) naming the Claude Code session behind it, which is the id the hooks report.
public enum ClaudeDesktop {
    /// The chat a record describes, when it's the one running `session`.
    public static func chat(inRecord data: Data, session: String) -> ClaudeChat? {
        guard let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = record["sessionId"] as? String, id.hasPrefix("local_") else { return nil }
        // After /clear the chat runs a new session; the earlier ids stay in the record too.
        let sessions = ["cliSessionId", "preClearCliSessionId", "unarchivedCliSessionId"].compactMap { record[$0] as? String }
        guard sessions.contains(session) else { return nil }
        let title = (record["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        // A chat is called "New session" until the app names it after the first turn.
        let named = title.flatMap { $0.isEmpty || $0 == "New session" ? nil : $0 }
        return ClaudeChat(id: id, title: named)
    }

    /// Opens the session's chat in the app. A session with no chat there (started in Terminal)
    /// gets the app's resume link instead, which brings it into the app.
    public static func link(session: String, chat: String?) -> URL? {
        var url = URLComponents()
        url.scheme = "claude"
        if let chat {
            url.host = "code"
            url.path = "/continue"
            url.queryItems = [URLQueryItem(name: "session", value: chat)]
        } else {
            // The resume link only takes a Claude Code session id, which is a UUID.
            guard UUID(uuidString: session) != nil else { return nil }
            url.host = "resume"
            url.queryItems = [URLQueryItem(name: "session", value: session)]
        }
        return url.url
    }
}
