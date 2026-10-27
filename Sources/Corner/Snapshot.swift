import AppKit
import CornerKit
import SwiftUI

/// `Corner --snapshot <folder>` draws each widget state to PNGs with sample data and exits.
/// It needs no Screen Recording permission, so it works for checking layout and for the README.
@MainActor
enum Snapshot {
    static func write(to dir: URL) {
        Glass.flat = true
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date()

        var state = AppState()
        let focus = CTimer(label: "Focus", duration: 1500, startedAt: now.addingTimeInterval(-378))
        state.timers = [focus]
        state.countdowns = [
            Countdown(label: "Release freeze", icon: "paperplane", target: now.addingTimeInterval(101_520), since: now.addingTimeInterval(-86_400)),
            Countdown(label: "Tracker run", icon: "chart.bar", target: now.addingTimeInterval(20_000), since: now.addingTimeInterval(-66_400), repeatRule: .weekdays),
        ]
        state.meetings = [
            Meeting(id: "design@1", title: "Design review", start: now.addingTimeInterval(-1500), end: now.addingTimeInterval(300),
                    calendarTitle: "Work", colorHex: "#AF52DE"),
            Meeting(id: "standup@1", title: "Standup", start: now.addingTimeInterval(680), end: now.addingTimeInterval(2480),
                    calendarTitle: "Work", colorHex: "#0A84FF", joinURL: URL(string: "https://meet.google.com/abc-defg-hij")),
        ]
        state.stopwatch.accumulated = 728
        let yesterday = now.addingTimeInterval(-86_400)
        for (text, added, done) in [
            ("Send the weekly status update", yesterday.addingTimeInterval(-3600), true),
            ("Book the dentist", yesterday, false),
            ("Review the deploy PR", now.addingTimeInterval(-10_800), false),
            ("Check the queue after the deploy", now.addingTimeInterval(-7200), true),
            ("Update the incident doc", now.addingTimeInterval(-3600), false),
        ] {
            state.addTodo(text, at: added)
            if done { state.toggleTodo(state.todos[state.todos.count - 1].id, at: added.addingTimeInterval(1800)) }
        }
        _ = state.advance(to: now)

        var overtime = state
        overtime.timers = [CTimer(label: "Focus", duration: 1500, startedAt: now.addingTimeInterval(-1572))]
        _ = overtime.advance(to: now)

        var soon = state
        soon.timers = []
        soon.meetings = []
        soon.countdowns.append(Countdown(label: "Lunch", icon: "fork.knife", target: now.addingTimeInterval(600), since: now.addingTimeInterval(-3000)))

        var meeting = state
        meeting.timers = []

        var meetingNow = meeting
        meetingNow.meetings = [Meeting(id: "standup@2", title: "Standup", start: now.addingTimeInterval(-70), end: now.addingTimeInterval(1730))]

        var idle = AppState()
        idle.settings = state.settings

        let corners = [("timer", state), ("overtime", overtime), ("countdown", soon), ("meeting", meeting), ("meeting-now", meetingNow), ("clock", idle)]
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            for (name, s) in corners {
                let store = Store(preview: s)
                store.tick()
                render(CornerFaceView(face: store.state.face(at: now), size: 100, hovering: false),
                       scheme: scheme, to: dir.appendingPathComponent("corner-\(name)-\(suffix).png"))
            }
            // Shrink mode: resting size next to full size, and the 12-hour corner and card.
            var twelve = state
            twelve.settings.clockStyle = .h12
            var twelveIdle = idle
            twelveIdle.settings.clockStyle = .h12
            let full = CornerSize.medium.points
            let mini = CornerSize.medium.miniPoints
            for (name, s, size) in [("mini-timer", state, mini), ("mini-clock", twelveIdle, mini), ("full-clock-12h", twelveIdle, full)] {
                let store = previewStore(s)
                store.tick()
                render(CornerFaceView(face: store.state.face(at: now), size: size, fullSize: full, hovering: false)
                    .frame(width: full, height: full, alignment: .topLeading),
                       scheme: scheme, to: dir.appendingPathComponent("corner-\(name)-\(suffix).png"))
            }
            render(CardView(store: previewStore(twelve), ui: UIModel()).fixedSize(),
                   scheme: scheme, to: dir.appendingPathComponent("card-12h-\(suffix).png"))
            // Claude Code activity: three sessions in the card, and the corner in each state.
            var claude = state
            claude.settings.showClaude = true
            claude.timers = []
            _ = claude.apply(ClaudeEvent(kind: .promptSubmitted, sessionID: "a", cwd: "/Users/me/Desktop/Media",
                                         prompt: "make corner smallest on hover and show it like now with animation"), at: now.addingTimeInterval(-252))
            _ = claude.apply(ClaudeEvent(kind: .promptSubmitted, sessionID: "b", cwd: "/Users/me/Desktop/Corner", prompt: "build it"),
                             at: now.addingTimeInterval(-363))
            _ = claude.apply(ClaudeEvent(kind: .notification, sessionID: "b", cwd: "/Users/me/Desktop/Corner",
                                         message: "Claude needs your permission to use Bash", notificationType: "permission_prompt"),
                             at: now.addingTimeInterval(-20))
            _ = claude.apply(ClaudeEvent(kind: .promptSubmitted, sessionID: "c", cwd: "/Users/me/Desktop/dlq-debug",
                                         prompt: "why are these messages in the DLQ?"), at: now.addingTimeInterval(-543))
            _ = claude.apply(ClaudeEvent(kind: .stopped, sessionID: "c",
                                         lastMessage: "135 callbacks failed on a missing mediaId; details below."), at: now.addingTimeInterval(-120))
            // Chats opened in Claude desktop carry its titles; "c" ran in Terminal, so it keeps its folder name.
            claude.setClaudeChats(["a": ClaudeChat(id: "local_a", title: "Shrink the corner on hover"),
                                   "b": ClaudeChat(id: "local_b", title: "Corner app build")])
            render(CardView(store: previewStore(claude), ui: UIModel()).fixedSize(),
                   scheme: scheme, to: dir.appendingPathComponent("card-claude-\(suffix).png"))
            var working = claude, needs = claude, done = claude
            working.claudeSessions.removeAll { $0.id != "a" }
            working.meetings = []
            working.countdowns = []
            needs.claudeSessions.removeAll { $0.id != "b" }
            done.claudeSessions.removeAll { $0.id != "c" }
            for (name, s) in [("claude-working", working), ("claude-needs", needs), ("claude-done", done)] {
                render(CornerFaceView(face: s.face(at: now), size: 100, hovering: false),
                       scheme: scheme, to: dir.appendingPathComponent("corner-\(name)-\(suffix).png"))
            }
            // Each companion doing each thing, at a moment that shows it off, and the climb step by step.
            let moments: [(CompanionActivity, Double)] = [
                (.sit, 0.1), (.wag, 0.2), (.play, 0.6), (.play, 1.0), (.walk, 0.5), (.sleep, 1.0), (.wake, 0.5), (.greet, 0.3),
            ]
            let climbTimes: [Double] = [0.3, 1.2, 2.4, 3.6, 4.5, 4.7, 5.1, 5.6]
            func cell(_ kind: CompanionKind, _ activity: CompanionActivity, _ t: Double) -> some View {
                let frames = CompanionFrames.frames(kind, activity)
                let index = min(frames.count - 1, Int(t * CompanionFrames.loop(activity).fps))
                return ZStack(alignment: .topLeading) {
                    ThemedBackground(kind: .quarter)
                    QuarterArc(inset: 6).stroke(Color.primary.opacity(0.12), lineWidth: 4.8)
                    Image(decorative: frames[index], scale: 1).interpolation(.none).resizable().clipShape(QuarterShape())
                }
                .frame(width: 120, height: 120)
            }
            render(VStack(alignment: .leading, spacing: 8) {
                ForEach(CompanionKind.allCases, id: \.self) { kind in
                    HStack(spacing: 8) {
                        ForEach(moments.indices, id: \.self) { i in cell(kind, moments[i].0, moments[i].1) }
                    }
                    HStack(spacing: 8) {
                        ForEach(climbTimes.indices, id: \.self) { i in cell(kind, .climb, climbTimes[i]) }
                    }
                }
            }.padding(8).themed(Theme.named(.midnight)),
                   scheme: scheme, to: dir.appendingPathComponent("companions-\(suffix).png"))
            renderWindow(SettingsView(store: previewStore(twelve), connectCalendar: {}),
                         size: CGSize(width: SettingsView.width, height: SettingsView.height),
                         scheme: scheme, to: dir.appendingPathComponent("settings-\(suffix).png"))
            // The corner in each corner of the screen: a timer, a companion, and the card in the bottom right.
            render(VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(ScreenCorner.allCases, id: \.self) { corner in
                        CornerFaceView(face: state.face(at: now), size: 100, hovering: false)
                            .frame(width: 100, height: 100)
                            .padding(4)
                            .background(Color.primary.opacity(0.06))
                            .environment(\.screenCorner, corner)
                    }
                }
                // Companions are layers the renderer can't capture, so their frames are drawn directly.
                ForEach([(CompanionKind.ninja, CompanionActivity.sit, 0.3), (.ninja, .climb, 3.0), (.cat, .climb, 2.5)].indices, id: \.self) { row in
                    let (kind, activity, t) = [(CompanionKind.ninja, CompanionActivity.sit, 0.3), (.ninja, .climb, 3.0), (.cat, .climb, 2.5)][row]
                    HStack(spacing: 10) {
                        ForEach(ScreenCorner.allCases, id: \.self) { corner in
                            let frames = CompanionFrames.frames(kind, activity, corner: corner)
                            ZStack(alignment: corner.alignment) {
                                ThemedBackground(kind: .quarter)
                                Image(decorative: frames[min(frames.count - 1, Int(t * CompanionFrames.loop(activity).fps))], scale: 1)
                                    .interpolation(.none).resizable().clipShape(QuarterShape(corner: corner))
                            }
                            .frame(width: 100, height: 100)
                            .padding(4)
                            .background(Color.primary.opacity(0.06))
                            .environment(\.screenCorner, corner)
                        }
                    }
                }
                CardView(store: previewStore(twelve), ui: UIModel()).fixedSize().environment(\.screenCorner, .bottomRight)
            }.padding(8),
                   scheme: scheme, to: dir.appendingPathComponent("corners-\(suffix).png"))
            // Every corner size side by side, with long labels, to check text size and placement.
            var longName = working
            _ = longName.apply(ClaudeEvent(kind: .promptSubmitted, sessionID: "a", cwd: "/Users/me/Desktop/inventory-apis"),
                               at: now.addingTimeInterval(-1656))
            var leave = idle
            leave.countdowns = [Countdown(label: "Leave", icon: "sun.max", target: now.addingTimeInterval(8000), since: now.addingTimeInterval(-20_000))]
            var twelveTimer = twelve
            twelveTimer.meetings = []
            let rows: [AppState] = [twelveIdle, twelveTimer, leave, longName, needs, done]
            render(VStack(alignment: .leading, spacing: 8) {
                ForEach(rows.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(CornerSize.allCases, id: \.self) { size in
                            CornerFaceView(face: rows[i].face(at: now), size: size.points, hovering: false)
                                .frame(width: 120, height: 120, alignment: .topLeading)
                        }
                    }
                }
            }.padding(8).themed(Theme.named(.midnight)),
                   scheme: scheme, to: dir.appendingPathComponent("corner-sizes-\(suffix).png"))
            if scheme == .dark {
                // The website's Claude Code section: the three corner states and the card's Claude block.
                let aurora = Theme.named(.aurora)
                for (name, s) in [("working", working), ("needs", needs), ("done", done)] {
                    render(CornerFaceView(face: s.face(at: now), size: 100, hovering: false).themed(aurora),
                           scheme: .dark, backdrop: false, to: dir.appendingPathComponent("site-claude-\(name).png"))
                }
                render(ClaudeSection(store: previewStore(claude), ui: UIModel(), now: now)
                        .padding(14)
                        .frame(width: 300)
                        .background(ThemedBackground(kind: .card))
                        .overlay(UnevenRoundedRectangle(bottomTrailingRadius: Masks.cardRadius)
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                        .themed(aurora),
                       scheme: .dark, backdrop: false, to: dir.appendingPathComponent("site-claude-card.png"))
            }

            for (name, tone) in [("tucked", Tone.normal), ("tucked-alert", Tone.alert)] {
                render(TuckedTab(tone: tone).frame(width: 100, height: 100, alignment: .topLeading),
                       scheme: scheme, to: dir.appendingPathComponent("corner-\(name)-\(suffix).png"))
            }
            let ui = UIModel()
            ui.expanded = true
            render(CardView(store: previewStore(state), ui: ui).fixedSize(),
                   scheme: scheme, to: dir.appendingPathComponent("card-\(suffix).png"))
            ui.quickAddActive = true
            render(CardView(store: previewStore(state), ui: ui).fixedSize(),
                   scheme: scheme, to: dir.appendingPathComponent("card-quickadd-\(suffix).png"))
            ui.quickAddActive = false
            render(HistoryView(store: previewStore(state), flat: true).frame(width: 520, height: 470),
                   scheme: scheme, to: dir.appendingPathComponent("history-\(suffix).png"))
            // Every theme side by side: corner on top, card underneath.
            let themed = Theme.all.map { theme -> (Theme, Store) in
                var s = state
                s.settings.theme = theme.id
                let store = previewStore(s)
                store.tick()
                return (theme, store)
            }
            let sheet = HStack(alignment: .top, spacing: 28) {
                ForEach(themed.indices, id: \.self) { i in
                    let (theme, store) = themed[i]
                    VStack(alignment: .leading, spacing: 14) {
                        Text(theme.name).font(.system(size: 15, weight: .semibold))
                        CornerFaceView(face: store.state.face(at: now), size: 100, hovering: false).themed(theme)
                        CardView(store: store, ui: ui).fixedSize().themed(theme)
                    }
                }
            }
            render(sheet, scheme: scheme, scale: 1, to: dir.appendingPathComponent("themes-\(suffix).png"))

            if scheme == .dark {
                // The website's theme switcher: the card in every theme, on the site's background.
                for theme in Theme.all {
                    var s = state
                    s.settings.theme = theme.id
                    render(CardView(store: previewStore(s), ui: ui).fixedSize().themed(theme),
                           scheme: .dark, backdrop: false, fill: Color(rgb: 0x0B0D14),
                           to: dir.appendingPathComponent("site-theme-\(theme.id.rawValue).png"))
                }
                // The corner's states, for the feature grid.
                for (name, s) in [("timer", state), ("meeting", meeting), ("overtime", overtime), ("clock", idle)] {
                    let store = themedStore(s, .aurora)
                    render(CornerFaceView(face: store.state.face(at: now), size: 100, hovering: false).themed(Theme.named(.aurora)),
                           scheme: .dark, backdrop: false, to: dir.appendingPathComponent("site-state-\(name).png"))
                }
                let mini = themedStore(state, .aurora)
                render(CornerFaceView(face: mini.state.face(at: now), size: CornerSize.medium.miniPoints, fullSize: 100, hovering: false)
                        .themed(Theme.named(.aurora)),
                       scheme: .dark, backdrop: false, to: dir.appendingPathComponent("site-state-mini.png"))
            }

            // Transparent cut-outs for the website's hero.
            let auroraState: AppState = {
                var s = state
                s.settings.theme = .aurora
                return s
            }()
            let aurora = previewStore(auroraState)
            render(CardView(store: aurora, ui: ui).fixedSize().themed(Theme.named(.aurora)),
                   scheme: scheme, backdrop: false, to: dir.appendingPathComponent("site-card-\(suffix).png"))
            render(CornerFaceView(face: meetingStore(meeting).state.face(at: now), size: 100, hovering: false)
                    .themed(Theme.named(.aurora)),
                   scheme: scheme, backdrop: false, to: dir.appendingPathComponent("site-corner-\(suffix).png"))
            let unconnected = previewStore(state)
            unconnected.calendarAccess = .notDetermined
            render(CardView(store: unconnected, ui: ui).fixedSize(),
                   scheme: scheme, to: dir.appendingPathComponent("card-connect-\(suffix).png"))
        }
    }

    private static func themedStore(_ state: AppState, _ theme: ThemeID) -> Store {
        var s = state
        s.settings.theme = theme
        let store = previewStore(s)
        store.tick()
        return store
    }

    private static func meetingStore(_ state: AppState) -> Store {
        var s = state
        s.settings.theme = .aurora
        let store = previewStore(s)
        store.tick()
        return store
    }

    private static func previewStore(_ state: AppState) -> Store {
        let store = Store(preview: state)
        store.calendarAccess = .granted
        return store
    }

    /// Draws the view over a stand-in desktop so the corner reads as it does on screen.
    /// `backdrop: false` gives an unpadded image for the website: transparent, or on `fill`.
    /// Native controls (pop-up menus, segmented pickers, forms) don't come out of ImageRenderer, so
    /// windows like Settings are drawn by AppKit in an offscreen window instead.
    static func renderWindow<V: View>(_ view: V, size: CGSize, scheme: ColorScheme, to url: URL) {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -30000, y: -30000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func render<V: View>(_ view: V, scheme: ColorScheme, scale: CGFloat = 2, backdrop: Bool = true,
                                        fill: Color? = nil, to url: URL) {
        let framed = view
            .padding(.trailing, backdrop ? 40 : 0)
            .padding(.bottom, backdrop ? 40 : 0)
            .background(backdrop ? (scheme == .dark ? Color(white: 0.16) : Color(white: 0.78)) : (fill ?? .clear))
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = scale
        guard let image = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
