import AppKit
import Combine
import CornerKit
import SwiftUI

final class CornerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Buttons respond to the first click even though the panel never activates the app.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The borderless panel pinned to the top-left of the main screen, just under the menu bar.
///
/// Mouse handling: the window is a square, but only the quarter disc should take clicks. The
/// panel ignores the mouse until the cursor is inside the curve, so the gap between the curve
/// and the square's corner clicks through to whatever is behind it.
@MainActor
final class PanelController {
    private let store: Store
    private let ui: UIModel
    private let panel: CornerPanel
    private var cardSize = CGSize(width: 280, height: 420)
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    private var lastInside = Date()
    private var fullScreen = false
    private var collapsing = false
    private var collapseGeneration = 0
    private var scrollAccumulator: CGFloat = 0
    private var restTimer: DispatchWorkItem?

    private static let collapsedScale: CGFloat = 0.36

    init(store: Store, ui: UIModel) {
        self.store = store
        self.ui = ui
        panel = CornerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        // Plain clicks never steal keyboard focus; only the quick-add field does.
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true

        let host = FirstClickHostingView(rootView: RootView(store: store, ui: ui))
        host.sizingOptions = []
        panel.contentView = host

        ui.expand = { [weak self] in self?.expand() }
        ui.collapse = { [weak self] in self?.collapse() }
        ui.startQuickAdd = { [weak self] in self?.startQuickAdd() }
        ui.endQuickAdd = { [weak self] in self?.endQuickAdd() }
        ui.editTodo = { [weak self] id in self?.startEditing(id) }
        ui.endEditing = { [weak self] in self?.endEditing() }
        ui.cardSizeChanged = { [weak self] size in self?.cardSizeChanged(size) }

        // $state fires before the new value is stored, so act on the next turn of the run loop.
        store.$state
            .map(\.settings.cornerSize)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.layout() } }
            }
            .store(in: &cancellables)
        store.$state
            .map { "\($0.settings.hidden)|\($0.settings.restStyle.rawValue)" }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.applyVisibility() } }
            }
            .store(in: &cancellables)

        refreshFullScreen()
        layout()
        installMonitors()
        observeEnvironment()
        applyVisibility()
    }

    // MARK: - Hide, tuck and shrink

    /// Shows or hides the panel, and puts the corner in its resting form if the pointer is elsewhere.
    private func applyVisibility() {
        let prefs = store.state.settings
        if prefs.hidden {
            if ui.expanded { collapse() } else { panel.orderOut(nil) }
        } else {
            panel.orderFrontRegardless()
        }
        let resting = !ui.expanded && !insideQuarter(NSEvent.mouseLocation)
        let tuck = prefs.restStyle == .tucked && resting
        let shrink = prefs.restStyle == .mini && resting
        if ui.tucked != tuck { setTucked(tuck) }
        if ui.shrunk != shrink { setShrunk(shrink) }
    }

    private func setTucked(_ tucked: Bool) {
        cancelRest()
        withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) { ui.tucked = tucked }
        if tucked {
            ui.hovering = false
            panel.ignoresMouseEvents = true
        }
    }

    private func setShrunk(_ shrunk: Bool) {
        cancelRest()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { ui.shrunk = shrunk }
        if shrunk { ui.hovering = false }
    }

    /// Goes back to resting once the pointer has been gone for a moment, so brushing past doesn't flicker it.
    private func scheduleRest() {
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.restTimer = nil
                guard !self.ui.expanded, !self.insideQuarter(NSEvent.mouseLocation) else { return }
                switch self.store.state.settings.restStyle {
                case .tucked: self.setTucked(true)
                case .mini: self.setShrunk(true)
                case .full: break
                }
            }
        }
        restTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func cancelRest() {
        restTimer?.cancel()
        restTimer = nil
    }

    /// The pointer pressed against the left screen edge, alongside the corner. Chrome's and other
    /// apps' window controls sit a little in from the edge, so reaching for them never triggers this.
    private func pushedIntoEdge(_ p: NSPoint) -> Bool {
        guard let screen = NSScreen.screens.first else { return false }
        let f = panel.frame
        let band = store.state.settings.cornerSize.points * 1.2
        return p.x <= screen.frame.minX + 1 && p.y <= f.maxY + 1 && p.y >= f.maxY - band
    }

    // MARK: - Expand and collapse

    func expand() {
        if ui.expanded {
            // Clicked again while the close animation was running: reverse it.
            guard collapsing else { return }
            collapsing = false
            collapseGeneration += 1
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                ui.cardScale = 1
                ui.cardOpacity = 1
            }
            return
        }
        store.acknowledgeAlerts()
        cancelRest()
        ui.tucked = false
        ui.shrunk = false
        // Quick add and "Open Corner" still work while hidden; the card goes away again on close.
        if store.state.settings.hidden { panel.orderFrontRegardless() }
        ui.hovering = false
        ui.cardScale = Self.collapsedScale
        ui.cardOpacity = 0
        ui.expanded = true
        lastInside = Date()
        panel.ignoresMouseEvents = false
        layout()
        DispatchQueue.main.async { [ui] in
            MainActor.assumeIsolated {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                    ui.cardScale = 1
                    ui.cardOpacity = 1
                }
            }
        }
    }

    func collapse() {
        guard ui.expanded, !collapsing else { return }
        collapsing = true
        collapseGeneration += 1
        let generation = collapseGeneration
        ui.quickAddActive = false
        ui.editingTodo = nil
        releaseKeyFocus()
        withAnimation(.easeIn(duration: 0.14)) {
            ui.cardScale = Self.collapsedScale
            ui.cardOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.collapseGeneration == generation else { return }
                self.collapsing = false
                self.ui.expanded = false
                self.layout()
                if self.store.state.settings.hidden {
                    self.panel.orderOut(nil)
                } else if !self.insideQuarter(NSEvent.mouseLocation) {
                    switch self.store.state.settings.restStyle {
                    case .tucked: self.setTucked(true)
                    case .mini: self.setShrunk(true)
                    case .full: break
                    }
                }
                self.trackMouse()
            }
        }
    }

    func toggleQuickAdd() {
        if ui.quickAddActive {
            collapse()
        } else {
            startQuickAdd()
        }
    }

    func startQuickAdd() {
        expand()
        ui.quickAddActive = true
        lastInside = Date()
        // A non-activating panel can take the keyboard without pulling you out of your current app.
        panel.makeKeyAndOrderFront(nil)
    }

    func endQuickAdd() {
        ui.quickAddActive = false
        // Keep the card up long enough to see what was added.
        lastInside = Date()
        releaseKeyFocus()
    }

    private func startEditing(_ id: UUID) {
        ui.editingTodo = id
        lastInside = Date()
        panel.makeKeyAndOrderFront(nil)
    }

    private func endEditing() {
        ui.editingTodo = nil
        lastInside = Date()
        releaseKeyFocus()
    }

    /// Ordering the panel out and back hands keyboard focus back to the app you were in.
    private func releaseKeyFocus() {
        guard panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    // MARK: - Layout

    private func cardSizeChanged(_ size: CGSize) {
        debugLayout("card measured \(size)")
        guard size.width > 0, size.height > 0, size != cardSize else { return }
        cardSize = size
        // The measurement can arrive in the middle of a setFrame (AppKit redraws inside it), so
        // resize on the next pass rather than re-entering.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.ui.expanded else { return }
                self.layout()
            }
        }
    }

    func layout() {
        guard let screen = NSScreen.screens.first else { return }
        // In a full-screen app the menu bar is hidden, so the corner moves up to the very top.
        let top = fullScreen ? screen.frame.maxY : screen.visibleFrame.maxY
        let left = screen.visibleFrame.minX
        let size: CGSize
        if ui.expanded {
            size = cardSize
        } else {
            // Room for the 8% hover growth.
            let side = ceil(store.state.settings.cornerSize.points * 1.1)
            size = CGSize(width: side, height: side)
        }
        panel.setFrame(NSRect(x: left, y: top - size.height, width: size.width, height: size.height), display: true)
        debugLayout("layout wanted \(size), window is \(panel.frame.size)")
    }

    /// `CORNER_DEBUG_LAYOUT=1` prints sizing decisions to stderr.
    private func debugLayout(_ message: @autoclosure () -> String) {
        guard ProcessInfo.processInfo.environment["CORNER_DEBUG_LAYOUT"] != nil else { return }
        FileHandle.standardError.write(Data("Corner layout: \(message())\n".utf8))
    }

    private func observeEnvironment() {
        let workspace = NSWorkspace.shared.notificationCenter
        let names = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didWakeNotification,
        ]
        for name in names {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Wait out the Space-switch animation before checking.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    MainActor.assumeIsolated { self?.refreshFullScreen() }
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        })
    }

    /// A full-screen app shows up as another app's normal-level window exactly covering the main screen.
    private func refreshFullScreen() {
        guard let screen = NSScreen.screens.first else { return }
        let full = CGRect(origin: .zero, size: screen.frame.size)
        let me = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let covered = windows.contains { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? pid_t) != me,
                  let bounds = w[kCGWindowBounds as String],
                  let rect = CGRect(dictionaryRepresentation: bounds as! CFDictionary) else { return false }
            return rect == full
        }
        if covered != fullScreen {
            fullScreen = covered
            layout()
        }
    }

    // MARK: - Mouse and keyboard

    private func installMonitors() {
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.trackMouse() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.trackMouse() }
            return event
        }) { monitors.append(m) }
        // Global monitors only see clicks in other apps, which is exactly "outside the card".
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedOutside() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.scrolled(event) ?? false }
            return handled ? nil : event
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.pressedEscape(event) ?? false }
            return handled ? nil : event
        }) { monitors.append(m) }
    }

    /// Where the panel should take clicks right now. Tucked or hidden, nowhere.
    private func contains(_ p: NSPoint) -> Bool {
        let f = panel.frame
        if ui.expanded {
            return p.x >= f.minX - 1 && p.x <= f.maxX && p.y >= f.minY && p.y <= f.maxY + 1
        }
        if ui.tucked || store.state.settings.hidden { return false }
        if ui.shrunk { return inside(p, radius: store.state.settings.cornerSize.miniPoints) }
        return insideQuarter(p)
    }

    /// Inside the full-size quarter circle, whether or not it's showing.
    private func insideQuarter(_ p: NSPoint) -> Bool {
        inside(p, radius: store.state.settings.cornerSize.points * (ui.hovering ? 1.08 : 1))
    }

    private func inside(_ p: NSPoint, radius: Double) -> Bool {
        let f = panel.frame
        let dx = p.x - f.minX
        let dy = f.maxY - p.y
        return dx >= -1 && dy >= -1 && dx * dx + dy * dy <= radius * radius
    }

    private func trackMouse() {
        let p = NSEvent.mouseLocation
        let prefs = store.state.settings
        if !ui.expanded && !prefs.hidden {
            switch prefs.restStyle {
            case .tucked:
                if ui.tucked {
                    if pushedIntoEdge(p) { setTucked(false) }
                } else if insideQuarter(p) || pushedIntoEdge(p) {
                    cancelRest()
                } else if restTimer == nil {
                    scheduleRest()
                }
            case .mini:
                if ui.shrunk {
                    if contains(p) { setShrunk(false) }
                } else if insideQuarter(p) {
                    cancelRest()
                } else if restTimer == nil {
                    scheduleRest()
                }
            case .full:
                break
            }
        }
        let inside = contains(p)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        if inside { lastInside = Date() }
        // In shrink mode, growing to full size is the hover response.
        let hover = inside && !ui.expanded && prefs.restStyle != .mini
        if ui.hovering != hover {
            withAnimation(.easeOut(duration: 0.12)) { ui.hovering = hover }
        }
    }

    private func clickedOutside() {
        guard ui.expanded, !contains(NSEvent.mouseLocation) else { return }
        collapse()
    }

    /// Scrolling over the corner steps through timers, countdowns, the stopwatch and the clock.
    private func scrolled(_ event: NSEvent) -> Bool {
        guard !ui.expanded, contains(NSEvent.mouseLocation) else { return false }
        guard event.momentumPhase.isEmpty else { return true }
        scrollAccumulator += event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12
        guard abs(scrollAccumulator) >= 12 else { return true }
        let step = scrollAccumulator > 0 ? -1 : 1
        scrollAccumulator = 0
        let order = store.state.cycle(at: store.now)
        let current = store.state.face(at: store.now, manual: ui.manual).ref
        let index = order.firstIndex(of: current) ?? 0
        ui.manual = order[(index + step + order.count) % order.count]
        return true
    }

    private func pressedEscape(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53, ui.expanded else { return false }
        if ui.editingTodo != nil {
            endEditing()
        } else if ui.quickAddActive && store.state.timers.isEmpty && store.state.countdowns.isEmpty {
            collapse()
        } else if ui.quickAddActive {
            endQuickAdd()
        } else {
            collapse()
        }
        return true
    }

    /// Called every second: a safety net for missed mouse events, plus the auto-close.
    func tick() {
        trackMouse()
        guard ui.expanded, !collapsing, !ui.isTyping else { return }
        let seconds = store.state.settings.autoCollapseSeconds
        guard seconds > 0, Date().timeIntervalSince(lastInside) >= Double(seconds) else { return }
        collapse()
    }
}
