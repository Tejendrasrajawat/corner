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
    /// Where Claude Code writes the session's transcript, from its hooks.
    public var transcriptPath: String?

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
    public var transcriptPath: String?

    public init(kind: Kind, sessionID: String, cwd: String = "", prompt: String? = nil, message: String? = nil,
                notificationType: String? = nil, lastMessage: String? = nil, transcriptPath: String? = nil) {
        self.kind = kind
        self.sessionID = sessionID
        self.cwd = cwd
        self.prompt = prompt
        self.message = message
        self.notificationType = notificationType
        self.lastMessage = lastMessage
        self.transcriptPath = transcriptPath
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
                           lastMessage: object["last_assistant_message"] as? String,
                           transcriptPath: object["transcript_path"] as? String)
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
    /// A working session with no hook event for this long is checked against its transcript.
    public static let claudeQuietAfter: TimeInterval = 30

    /// Applies one hook event. Returns an alert when Claude needs you, or finished a turn long
    /// enough that you've probably looked away.
    public mutating func apply(_ event: ClaudeEvent, at now: Date) -> AlertEvent? {
        if event.kind == .sessionEnded {
            claudeSessions.removeAll { $0.id == event.sessionID }
            if pinned == .claude(event.sessionID) { pinned = nil }
            return nil
        }
        // Sessions that were already running when the hooks went in show up on their next event, if
        // it comes from a turn in progress. A subagent finishing doesn't mean Claude is working:
        // Claude Code's idle compaction runs as one long after a turn ends, and would otherwise
        // bring back a finished session as working, with no Stop to come.
        let known = claudeSessions.firstIndex { $0.id == event.sessionID }
        guard known != nil || Self.startsSession(event) else { return nil }
        let index = known ?? {
            claudeSessions.append(ClaudeSession(id: event.sessionID, cwd: event.cwd, status: .working, at: now))
            return claudeSessions.count - 1
        }()
        var s = claudeSessions[index]
        if !event.cwd.isEmpty { s.cwd = event.cwd }
        if let path = event.transcriptPath, !path.isEmpty { s.transcriptPath = path }
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
            // One finishing after the turn (the idle compaction) isn't part of it.
            if s.status != .done { s.subagentsDone += 1 }
        case .sessionEnded:
            break
        }
        claudeSessions[index] = s
        return alert
    }

    /// Whether an event from a session Corner isn't showing means a turn is under way.
    static func startsSession(_ event: ClaudeEvent) -> Bool {
        switch event.kind {
        case .promptSubmitted, .toolFinished, .stopped: true
        case .notification: notificationNeedsYou(event) && !isIdleReminder(event)
        case .subagentStopped, .sessionEnded: false
        }
    }

    /// Notification types that mean Claude is blocked on you. Unknown or missing types count, so
    /// a Claude Code that doesn't send the field still works.
    static func notificationNeedsYou(_ event: ClaudeEvent) -> Bool {
        guard let type = event.notificationType else { return true }
        return ["permission_prompt", "idle_prompt", "elicitation_dialog"].contains(type)
    }

    /// Claude Code's reminder, a minute after a turn ends, that it's waiting for your next message.
    static func isIdleReminder(_ event: ClaudeEvent) -> Bool {
        if let type = event.notificationType { return type == "idle_prompt" }
        return event.message?.localizedCaseInsensitiveContains("waiting for your input") == true
    }

    /// Ends turns the transcript shows are over though no Stop came: you interrupted it, it ended
    /// on an API error, or the Stop was missed. A session only counts once it's been quiet a while,
    /// which also waits out the moment between Claude's last message and its Stop hook. Returns
    /// whether anything changed.
    @discardableResult
    public mutating func reconcileClaude(_ turns: [String: ClaudeTranscript.Turn], at now: Date) -> Bool {
        var changed = false
        for i in claudeSessions.indices {
            var s = claudeSessions[i]
            guard s.status != .done, now.timeIntervalSince(s.updatedAt) >= Self.claudeQuietAfter,
                  case .ended(let at, let reply, let interrupted)? = turns[s.id],
                  now.timeIntervalSince(at ?? .distantPast) >= Self.claudeQuietAfter else { continue }
            s.status = .done
            s.finishedAt = max(s.startedAt, min(at ?? now, now))
            s.detail = nil
            s.reply = interrupted ? "Interrupted" : reply
            // You stopped it yourself, so it needn't catch your eye.
            s.seen = interrupted
            claudeSessions[i] = s
            changed = true
        }
        return changed
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

/// The end of a session's Claude Code transcript (JSONL, one entry a line). Claude Code sends no
/// Stop hook when you interrupt a turn or it ends on an API error, so for a session that has gone
/// quiet this tells whether the turn is still going.
public enum ClaudeTranscript {
    public enum Turn: Equatable, Sendable {
        case running
        /// `reply` is the start of Claude's last message, or of the error it ended on.
        case ended(at: Date?, reply: String?, interrupted: Bool)
    }

    /// How much of the end of the file to read: the last few entries, even with a long one.
    public static let tailLength = 256 * 1024

    /// What the last entries in `tail` say about the turn, or nil if none of them tell. When the
    /// tail was cut from a longer file, `fromStart` is false and its first, partial line is skipped.
    public static func lastTurn(in tail: Data, fromStart: Bool) -> Turn? {
        var lines = tail.split(separator: UInt8(ascii: "\n"))
        if !fromStart, !lines.isEmpty { lines.removeFirst() }
        // The Stop hooks ran, so the turn ended; the entry before it holds Claude's reply.
        var stopHooksRan = false
        var stoppedAt: Date?
        for line in lines.reversed() {
            guard let entry = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            let time = (entry["timestamp"] as? String).flatMap(date)
            let message = entry["message"] as? [String: Any]
            switch entry["type"] as? String {
            case "user":
                if stopHooksRan { return .ended(at: stoppedAt, reply: nil, interrupted: false) }
                if text(of: message).hasPrefix("[Request interrupted by user") {
                    return .ended(at: time, reply: nil, interrupted: true)
                }
                return .running
            case "assistant":
                let reply = Optional(AppState.snippet(text(of: message))).flatMap { $0.isEmpty ? nil : $0 }
                if stopHooksRan { return .ended(at: stoppedAt, reply: reply, interrupted: false) }
                // A tool call still running, or a message still being written, has no other reason.
                let reason = message?["stop_reason"] as? String
                if entry["isApiErrorMessage"] as? Bool == true || ["end_turn", "stop_sequence", "refusal"].contains(reason) {
                    return .ended(at: time, reply: reply, interrupted: false)
                }
                return .running
            case "system" where entry["subtype"] as? String == "stop_hook_summary" && !stopHooksRan:
                // A Stop hook can send Claude back to work.
                if entry["preventedContinuation"] as? Bool == true { return .running }
                stopHooksRan = true
                stoppedAt = time
            default:
                continue
            }
        }
        return stopHooksRan ? .ended(at: stoppedAt, reply: nil, interrupted: false) : nil
    }

    /// The text of a message, whose content is a string or a list of blocks.
    static func text(of message: [String: Any]?) -> String {
        switch message?["content"] {
        case let text as String:
            return text
        case let blocks as [[String: Any]]:
            return blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
        default:
            return ""
        }
    }

    static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
