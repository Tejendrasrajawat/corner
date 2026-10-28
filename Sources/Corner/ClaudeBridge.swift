import AppKit
import CornerKit

/// Connects Corner to Claude Code: installs the hook script, adds or removes its entries in
/// ~/.claude/settings.json, and reads the events the script leaves in Corner's inbox.
@MainActor
final class ClaudeBridge {
    private let store: Store
    private let folder: URL
    private var inbox: URL { folder.appendingPathComponent("claude-events.jsonl") }
    /// The inbox is renamed to this and read a tick later, so appends already in flight land first.
    private var reading: URL { folder.appendingPathComponent("claude-events.reading") }
    private var scriptURL: URL { folder.appendingPathComponent("claude-hook.sh") }

    static let settingsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    static let claudeAppID = "com.anthropic.claudefordesktop"

    init(store: Store) {
        self.store = store
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Corner", isDirectory: true)
        refreshInstalled()
        // Keep the script current with this version of Corner.
        if store.claudeHooksInstalled { try? writeScript() }
    }

    // MARK: - Inbox

    /// Called every second.
    func drain() {
        let fm = FileManager.default
        if fm.fileExists(atPath: reading.path) {
            if let text = try? String(contentsOf: reading, encoding: .utf8) {
                let items = text.split(whereSeparator: \.isNewline).compactMap { ClaudeEvent.parseInboxLine(String($0)) }
                store.applyClaude(items)
            }
            try? fm.removeItem(at: reading)
        }
        refreshChats()
        checkQuietSessions()
        if let size = (try? fm.attributesOfItem(atPath: inbox.path))?[.size] as? Int, size > 0 {
            try? fm.moveItem(at: inbox, to: reading)
        }
    }

    // MARK: - Turns that end without a Stop

    private var lastQuietCheck = Date.distantPast
    private var checkingQuiet = false

    /// Claude Code sends no Stop when you interrupt a turn or it ends on an API error, so every 15
    /// seconds each session that's gone quiet while working is checked against the end of its
    /// transcript. Files are read off the main thread.
    private func checkQuietSessions() {
        let now = Date()
        guard !checkingQuiet, store.state.settings.showClaude, now.timeIntervalSince(lastQuietCheck) >= 15 else { return }
        var transcripts: [String: String] = [:]
        for s in store.state.claudeSessions where s.status != .done && now.timeIntervalSince(s.updatedAt) >= AppState.claudeQuietAfter {
            transcripts[s.id] = s.transcriptPath
        }
        guard !transcripts.isEmpty else { return }
        lastQuietCheck = now
        checkingQuiet = true
        Task {
            let turns = await Task.detached(priority: .utility) { transcripts.compactMapValues { Self.lastTurn(transcript: $0) } }.value
            checkingQuiet = false
            store.reconcileClaude(turns)
        }
    }

    nonisolated static func lastTurn(transcript path: String) -> ClaudeTranscript.Turn? {
        guard let file = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? file.close() }
        guard let size = try? file.seekToEnd() else { return nil }
        let start = size > UInt64(ClaudeTranscript.tailLength) ? size - UInt64(ClaudeTranscript.tailLength) : 0
        guard (try? file.seek(toOffset: start)) != nil, let tail = try? file.readToEnd() else { return nil }
        return ClaudeTranscript.lastTurn(in: tail, fromStart: start == 0)
    }

    // MARK: - Claude desktop chats

    /// Each session's chat record in Claude desktop, once found.
    private var records: [String: URL] = [:]
    /// When Corner last looked for a session's chat and found none (a Terminal session, usually).
    private var missed: [String: Date] = [:]
    private var lastLookup = Date.distantPast
    private var lookingUp = false

    /// Matches sessions to their Claude desktop chats and keeps the titles current: right away for
    /// a session Corner hasn't looked for yet, otherwise every 10 seconds. Files are read off the
    /// main thread.
    private func refreshChats() {
        guard !lookingUp, store.state.settings.showClaude else { return }
        let now = Date()
        let sessions = store.state.claudeSessions.map(\.id)
        let known = records.filter { sessions.contains($0.key) }
        let unknown = sessions.filter { known[$0] == nil }
        let neverLooked = unknown.contains { missed[$0] == nil }
        guard !sessions.isEmpty, neverLooked || now.timeIntervalSince(lastLookup) >= 10 else { return }
        // Look again for a missing chat once a minute, in case the session is opened in the app.
        let wanted = unknown.filter { now.timeIntervalSince(missed[$0] ?? .distantPast) >= 60 }
        lastLookup = now
        lookingUp = true
        Task {
            let found = await Task.detached(priority: .utility) { Self.readChats(known: known, wanted: wanted) }.value
            lookingUp = false
            for (session, match) in found { records[session] = match.file }
            for session in wanted where found[session] == nil { missed[session] = now }
            records = records.filter { sessions.contains($0.key) }
            missed = missed.filter { sessions.contains($0.key) }
            store.setClaudeChats(found.mapValues(\.chat))
        }
    }

    struct FoundChat: Sendable {
        var file: URL
        var chat: ClaudeChat
    }

    nonisolated static let chatsFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Claude/claude-code-sessions", isDirectory: true)

    /// Re-reads the records already matched, and searches Claude's other records for the sessions
    /// in `wanted`. The app rewrites a chat's record as it runs, so only recent ones are read,
    /// newest first.
    nonisolated static func readChats(known: [String: URL], wanted: [String]) -> [String: FoundChat] {
        var found: [String: FoundChat] = [:]
        for (session, file) in known {
            if let data = try? Data(contentsOf: file), let chat = ClaudeDesktop.chat(inRecord: data, session: session) {
                found[session] = FoundChat(file: file, chat: chat)
            }
        }
        var left = Set(wanted).subtracting(found.keys)
        guard !left.isEmpty,
              let files = FileManager.default.enumerator(at: chatsFolder, includingPropertiesForKeys: [.contentModificationDateKey],
                                                         options: .skipsHiddenFiles) else { return found }
        let cutoff = Date().addingTimeInterval(-2 * 86_400)
        var recent: [(file: URL, modified: Date)] = []
        for case let file as URL in files where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if modified > cutoff { recent.append((file, modified)) }
        }
        for record in recent.sorted(by: { $0.modified > $1.modified }) where !left.isEmpty {
            guard let data = try? Data(contentsOf: record.file) else { continue }
            for session in left where data.range(of: Data(session.utf8)) != nil {
                if let chat = ClaudeDesktop.chat(inRecord: data, session: session) {
                    found[session] = FoundChat(file: record.file, chat: chat)
                    left.remove(session)
                }
            }
        }
        return found
    }

    // MARK: - Hooks

    func refreshInstalled() {
        let installed = (try? readSettings()).map(ClaudeHooks.isInstalled) ?? false
        if store.claudeHooksInstalled != installed { store.claudeHooksInstalled = installed }
    }

    /// Asks first, showing exactly what changes, then adds the hooks.
    func setUp() {
        let alert = NSAlert()
        alert.messageText = "Add Corner's hooks to Claude Code?"
        alert.informativeText = """
        Corner adds six hooks to ~/.claude/settings.json: UserPromptSubmit, PostToolUse, Notification, \
        Stop, SubagentStop and SessionEnd. Each runs a small script that writes the event to a file in \
        Corner's own folder, then exits. Nothing leaves your Mac, and Claude never waits more than a moment.

        Your current settings are kept, and a backup is saved as settings.json.corner-backup. Claude Code \
        picks up the change by itself.
        """
        alert.addButton(withTitle: "Add hooks")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            var settings = try readSettings()
            try writeScript()
            try backup()
            settings = ClaudeHooks.adding(to: settings)
            try write(settings)
            store.mutate { $0.settings.showClaude = true }
        } catch {
            show(error, doing: "add the hooks")
        }
        refreshInstalled()
    }

    func remove() {
        let alert = NSAlert()
        alert.messageText = "Remove Corner's hooks from Claude Code?"
        alert.informativeText = "Only Corner's six entries are removed from ~/.claude/settings.json; anything else there stays as it is."
        alert.addButton(withTitle: "Remove hooks")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try backup()
            try write(ClaudeHooks.removing(from: try readSettings()))
            store.mutate { s in
                s.settings.showClaude = false
                s.claudeSessions.removeAll()
            }
        } catch {
            show(error, doing: "remove the hooks")
        }
        refreshInstalled()
    }

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: Self.settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: Self.settingsURL)
        if data.isEmpty { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return object
    }

    private func write(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(at: Self.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: Self.settingsURL, options: .atomic)
    }

    private func backup() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Self.settingsURL.path) else { return }
        let copy = Self.settingsURL.deletingLastPathComponent().appendingPathComponent("settings.json.corner-backup")
        try? fm.removeItem(at: copy)
        try fm.copyItem(at: Self.settingsURL, to: copy)
    }

    private func writeScript() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try ClaudeHooks.script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    private func show(_ error: Error, doing what: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn't \(what)"
        alert.informativeText = "Corner couldn't read or write ~/.claude/settings.json, so nothing was changed. (\(error.localizedDescription))"
        alert.runModal()
    }

    // MARK: - Opening things

    static var claudeAppURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: claudeAppID)
    }

    static func openClaude() {
        guard let url = claudeAppURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Opens the session's chat in Claude desktop, looking the chat up first if Corner hasn't
    /// matched it yet. A Terminal session has no chat there, so the app is asked to resume it.
    static func openChat(session id: String, chat: String?) {
        guard claudeAppURL != nil else { return }
        Task {
            var chat = chat
            if chat == nil {
                chat = await Task.detached(priority: .userInitiated) { readChats(known: [:], wanted: [id])[id]?.chat.id }.value
            }
            if let url = ClaudeDesktop.link(session: id, chat: chat) {
                NSWorkspace.shared.open(url)
            } else {
                openClaude()
            }
        }
    }

    static func openChat(_ session: ClaudeSession) {
        openChat(session: session.id, chat: session.chatID)
    }

    static func showFolder(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }
}
