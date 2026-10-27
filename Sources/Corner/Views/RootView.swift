import CornerKit
import SwiftUI

/// Fills the panel; the panel controller resizes the window around whichever of the two is showing.
struct RootView: View {
    @ObservedObject var store: Store
    @ObservedObject var ui: UIModel

    var body: some View {
        let corner = store.state.settings.screenCorner
        ZStack(alignment: corner.alignment) {
            if ui.expanded {
                // Reported straight from a GeometryReader: a preference key here never fired when
                // the card appeared, which left the window at its default height and clipped the card.
                CardView(store: store, ui: ui)
                    .fixedSize()
                    .background(GeometryReader { geo in
                        Color.clear
                            .onAppear { ui.cardSizeChanged(geo.size) }
                            .onChange(of: geo.size) { _, size in ui.cardSizeChanged(size) }
                    })
                    .scaleEffect(ui.cardScale, anchor: corner.unitPoint)
                    .opacity(ui.cardOpacity)
            } else {
                let face = store.state.face(at: store.now, manual: ui.manual)
                let shrink = AnyTransition.scale(scale: 0.1, anchor: corner.unitPoint).combined(with: .opacity)
                if ui.tucked {
                    TuckedTab(tone: face.tone).transition(shrink)
                } else {
                    let cornerSize = store.state.settings.cornerSize
                    CornerFaceView(face: face, size: ui.shrunk ? cornerSize.miniPoints : cornerSize.points,
                                   fullSize: cornerSize.points, hovering: ui.hovering,
                                   animate: !store.state.settings.hidden, now: store.now)
                        .onTapGesture {
                            // The click that ends a drag isn't a tap.
                            if ui.justDragged { ui.justDragged = false } else { ui.expand() }
                        }
                        .contextMenu { cornerMenu(face) }
                        .transition(shrink)
                }
            }
        }
        // Explicit zero minimums keep the root no bigger than the window, so anything that doesn't
        // fit overflows downward instead of being centred and clipped at the top as well.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: corner.alignment)
        .themed(Theme.named(store.state.settings.theme))
        .environment(\.screenCorner, corner)
    }

    /// The clock, or one of the companions, as a single menu choice.
    private var idleChoice: Binding<String> {
        Binding(
            get: {
                let s = store.state.settings
                return s.idleFace == .clock ? "clock" : s.companion.rawValue
            },
            set: { choice in
                store.mutate { state in
                    if let kind = CompanionKind(rawValue: choice) {
                        state.settings.companion = kind
                        state.settings.idleFace = .companion
                    } else {
                        state.settings.idleFace = .clock
                    }
                }
            }
        )
    }

    @ViewBuilder
    private func cornerMenu(_ face: CornerFace) -> some View {
        let timer: CTimer? = {
            if case .timer(let id) = face.ref { return store.state.timers.first { $0.id == id } }
            return nil
        }()
        Button("Open") { ui.expand() }
        Button("Quick add…") { ui.startQuickAdd() }
        Button("To-do history…") { ui.openHistory() }
        if face.ref == .meeting, let m = store.state.featuredMeeting(at: store.now), let url = m.joinURL {
            Button("Join \(m.title)") { NSWorkspace.shared.open(url) }
        }
        if case .claude(let id) = face.ref, let s = store.state.claudeSessions.first(where: { $0.id == id }) {
            if ClaudeBridge.claudeAppURL != nil {
                Button("Open chat in Claude") { ClaudeBridge.openChat(s) }
            }
            Button("Show \(s.project) in Finder") { ClaudeBridge.showFolder(s.cwd) }
            Button("Dismiss") { store.dismissClaude(id) }
        }
        if case .countdown(let id) = face.ref, let c = store.state.countdowns.first(where: { $0.id == id }) {
            Divider()
            Button("\(CountdownClose(c, at: store.now, style: store.state.settings.clockStyle).title): \(c.label)") {
                store.closeCountdown(id)
            }
        }
        if let t = timer {
            Divider()
            Button(t.isRunning ? "Pause \(t.label)" : "Start \(t.label)") { store.toggleTimer(t.id) }
            Button("Add 5 minutes") { store.extendTimer(t.id, by: 300) }
            Button("Reset \(t.label)") { store.resetTimer(t.id) }
        }
        Divider()
        Menu("New timer") {
            ForEach([5, 15, 25, 45], id: \.self) { minutes in
                Button("\(minutes) minutes") { store.startTimer(minutes: minutes) }
            }
        }
        if face.ref != .clock {
            Button(store.state.pinned == face.ref ? "Unpin from corner" : "Pin to corner") { store.togglePin(face.ref) }
        }
        Divider()
        Picker("When nothing's on", selection: idleChoice) {
            Text("Clock").tag("clock")
            ForEach(CompanionKind.allCases, id: \.self) { kind in
                Text(kind.name).tag(kind.rawValue)
            }
        }
        Picker("Screen corner", selection: store.binding(\.settings.screenCorner)) {
            ForEach(ScreenCorner.allCases, id: \.self) { corner in
                Text(corner.name).tag(corner)
            }
        }
        Picker("When not in use", selection: store.binding(\.settings.restStyle)) {
            Text("Stay full size").tag(RestStyle.full)
            Text("Shrink, grow on hover").tag(RestStyle.mini)
            Text("Tuck into the edge").tag(RestStyle.tucked)
        }
        Button("Hide corner (⌃⌥C)") { store.mutate { $0.settings.hidden = true } }
        Button("Settings…") { ui.openSettings() }
    }
}
