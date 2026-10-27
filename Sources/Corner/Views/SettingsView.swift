import CornerKit
import SwiftUI

/// Two columns of cards: how Corner looks and behaves on the left, time, calendar and the rest on
/// the right. Related controls share a row so the window stays short.
struct SettingsView: View {
    @ObservedObject var store: Store
    let connectCalendar: () -> Void
    var setUpClaude: () -> Void = {}
    var removeClaude: () -> Void = {}
    @State private var launchAtLogin = LoginItem.isEnabled

    static let width: CGFloat = 900
    static let height: CGFloat = 640
    private static let column: CGFloat = 420

    private static let zones = (TimeZone.knownTimeZoneIdentifiers + ["UTC"]).sorted()
    private static let halfHours = Array(stride(from: 0, to: 24 * 60, by: 30))

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    theme
                    idleCorner
                    corner
                }
                .frame(width: Self.column)
                VStack(spacing: 16) {
                    clocks
                    calendar
                    claude
                    general
                }
                .frame(width: Self.column)
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .frame(width: Self.width, height: Self.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Left column

    private var theme: some View {
        SettingsCard("Theme", note: "Midnight has its own dark background; the others tint the glass and follow light or dark mode.") {
            HStack(spacing: 8) {
                ForEach(Theme.all, id: \.id) { theme in
                    ThemeSwatch(theme: theme, selected: store.state.settings.theme == theme.id) {
                        store.mutate { $0.settings.theme = theme.id }
                    }
                }
            }
        }
    }

    private var idleCorner: some View {
        SettingsCard("Idle corner", note: "Shown when nothing else needs the corner. Companions wander about, nap while you're away, and wave when you point at them.") {
            SettingsRow("When nothing's on") {
                Picker("", selection: store.binding(\.settings.idleFace)) {
                    Text("Show the clock").tag(IdleFace.clock)
                    Text("Show a companion").tag(IdleFace.companion)
                }
                .labelsHidden()
                .fixedSize()
            }
            HStack(spacing: 10) {
                ForEach(CompanionKind.allCases, id: \.self) { kind in
                    CompanionTile(kind: kind, selected: store.state.settings.idleFace == .companion
                                  && store.state.settings.companion == kind) {
                        store.mutate { s in
                            s.settings.companion = kind
                            s.settings.idleFace = .companion
                        }
                    }
                }
            }
        }
    }

    private var corner: some View {
        SettingsCard("Corner", note: "Drag the corner to any corner of the screen and let go. Tucked, it becomes a dot so what's under it stays clickable; push the pointer into that side of the screen to bring it back. ⌃⌥C hides or shows it.") {
            HStack(spacing: 16) {
                SettingsRow("Screen corner") {
                    Picker("", selection: store.binding(\.settings.screenCorner)) {
                        ForEach(ScreenCorner.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow("Size") {
                    Picker("", selection: store.binding(\.settings.cornerSize)) {
                        Text("S").tag(CornerSize.small)
                        Text("M").tag(CornerSize.medium)
                        Text("L").tag(CornerSize.large)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            SettingsRow("When not in use") {
                Picker("", selection: store.binding(\.settings.restStyle)) {
                    Text("Stay full size").tag(RestStyle.full)
                    Text("Shrink, grow on hover").tag(RestStyle.mini)
                    Text("Tuck into the edge").tag(RestStyle.tucked)
                }
                .labelsHidden()
            }
            HStack(spacing: 16) {
                SettingsRow("Close the card") {
                    Picker("", selection: store.binding(\.settings.autoCollapseSeconds)) {
                        Text("After 5 s").tag(5)
                        Text("After 10 s").tag(10)
                        Text("After 30 s").tag(30)
                        Text("Never").tag(0)
                    }
                    .labelsHidden()
                }
                Toggle("Hide it", isOn: store.binding(\.settings.hidden))
                    .fixedSize()
            }
        }
    }

    // MARK: Right column

    private var clocks: some View {
        SettingsCard("Clocks and workday") {
            SettingsRow("Time format") {
                Picker("", selection: store.binding(\.settings.clockStyle)) {
                    Text("24-hour").tag(ClockStyle.h24)
                    Text("12-hour").tag(ClockStyle.h12)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
            SettingsRow("Workday") {
                HStack(spacing: 6) {
                    hourPicker(store.binding(\.settings.workdayStartMinutes))
                    Text("to").foregroundStyle(.secondary)
                    hourPicker(store.binding(\.settings.workdayEndMinutes))
                }
            }
            zoneRow("Main clock", zone: store.binding(\.settings.primaryZone))
            ForEach(store.state.settings.secondaryZones.indices, id: \.self) { i in
                HStack {
                    zoneRow("Second clock", zone: secondaryZone(i))
                    Button {
                        store.mutate { s in
                            if i < s.settings.secondaryZones.count { s.settings.secondaryZones.remove(at: i) }
                        }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this clock")
                }
            }
            if store.state.settings.secondaryZones.count < 2 {
                Button("Add a clock") {
                    store.mutate { $0.settings.secondaryZones.append(ZoneClock(id: "UTC", label: "UTC")) }
                }
            }
        }
    }

    private var calendar: some View {
        SettingsCard("Calendar") {
            HStack(spacing: 16) {
                Toggle("Show my next meeting", isOn: store.binding(\.settings.showMeetings))
                Spacer(minLength: 0)
                SettingsRow("Alert me") {
                    Picker("", selection: store.binding(\.settings.meetingAlertMinutes)) {
                        Text("When it starts").tag(0)
                        Text("1 min before").tag(1)
                        Text("5 min before").tag(5)
                        Text("10 min before").tag(10)
                        Text("Never").tag(-1)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            switch store.calendarAccess {
            case .notDetermined:
                Button("Connect Calendar", action: connectCalendar)
            case .denied:
                HStack {
                    Text("Corner can't read your calendar.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings") { CalendarSource.openPrivacySettings() }
                }
            case .granted:
                // Two calendars a row.
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                          alignment: .leading, spacing: 6) {
                    ForEach(store.calendars) { cal in
                        Toggle(isOn: Binding(
                            get: { !store.state.settings.excludedCalendarIDs.contains(cal.id) },
                            set: { _ in store.toggleCalendar(cal.id) }
                        )) {
                            HStack(spacing: 6) {
                                Circle().fill(Color(hex: cal.colorHex) ?? .accentColor).frame(width: 8, height: 8)
                                Text(cal.title).lineLimit(1)
                            }
                        }
                        .help(cal.source)
                    }
                }
            }
        }
    }

    private var claude: some View {
        SettingsCard("Claude Code", note: "Shows when a session is working, needs you, or is done. Set up adds small hooks to ~/.claude/settings.json; nothing leaves your Mac.") {
            HStack {
                Toggle("Show Claude Code activity", isOn: store.binding(\.settings.showClaude))
                Spacer()
                Label(store.claudeHooksInstalled ? "Hooks set up" : "No hooks",
                      systemImage: store.claudeHooksInstalled ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(store.claudeHooksInstalled ? Color.green : Color.secondary)
                Button(store.claudeHooksInstalled ? "Remove…" : "Set up…") {
                    store.claudeHooksInstalled ? removeClaude() : setUpClaude()
                }
            }
        }
    }

    private var general: some View {
        SettingsCard("Alerts and startup") {
            HStack(spacing: 20) {
                Toggle("Chime", isOn: store.binding(\.settings.chime))
                Toggle("Notification", isOn: store.binding(\.settings.notify))
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        LoginItem.set(on)
                        launchAtLogin = LoginItem.isEnabled
                    }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Pieces

    private func hourPicker(_ minutes: Binding<Int>) -> some View {
        Picker("", selection: minutes) {
            ForEach(Self.halfHours, id: \.self) { Text(Format.minutesOfDay($0, style: store.state.settings.clockStyle)).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
    }

    /// Guarded so a binding to a just-removed clock can't read past the end of the array.
    private func secondaryZone(_ i: Int) -> Binding<ZoneClock> {
        Binding(
            get: {
                let zones = store.state.settings.secondaryZones
                return i < zones.count ? zones[i] : ZoneClock(id: "UTC", label: "UTC")
            },
            set: { value in
                store.mutate { s in
                    if i < s.settings.secondaryZones.count { s.settings.secondaryZones[i] = value }
                }
            }
        )
    }

    private func zoneRow(_ title: String, zone: Binding<ZoneClock>) -> some View {
        SettingsRow(title) {
            HStack(spacing: 6) {
                Picker("", selection: Binding(
                    get: { zone.wrappedValue.id },
                    set: { zone.wrappedValue = ZoneClock(id: $0, label: ZoneClock.defaultLabel(for: $0)) }
                )) {
                    // macOS's list leaves out UTC and older names like Asia/Calcutta, which would
                    // show as an empty pop-up, so the current one is always in it.
                    ForEach(Self.zones.contains(zone.wrappedValue.id) ? Self.zones : [zone.wrappedValue.id] + Self.zones,
                            id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
                TextField("Label", text: zone.label)
                    .frame(width: 64)
                    .labelsHidden()
            }
        }
    }
}

/// A titled group of settings on a rounded panel, with an optional line of explanation under it.
struct SettingsCard<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder let content: Content

    init(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            if let note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A label with its control beside it.
struct SettingsRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: Control

    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title).fixedSize()
            Spacer(minLength: 8)
            control
        }
    }
}
