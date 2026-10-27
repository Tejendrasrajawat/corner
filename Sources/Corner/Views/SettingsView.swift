import CornerKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: Store
    let connectCalendar: () -> Void
    var setUpClaude: () -> Void = {}
    var removeClaude: () -> Void = {}
    @State private var launchAtLogin = LoginItem.isEnabled

    private static let zones = TimeZone.knownTimeZoneIdentifiers.sorted()
    private static let halfHours = Array(stride(from: 0, to: 24 * 60, by: 30))

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                    ForEach(Theme.all, id: \.id) { theme in
                        ThemeSwatch(theme: theme, selected: store.state.settings.theme == theme.id) {
                            store.mutate { $0.settings.theme = theme.id }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Theme")
            } footer: {
                Text("Midnight has its own dark background. The others tint the glass, so they follow your Mac's light or dark mode.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Section("Clocks") {
                Picker("Time format", selection: store.binding(\.settings.clockStyle)) {
                    Text("24-hour").tag(ClockStyle.h24)
                    Text("12-hour").tag(ClockStyle.h12)
                }
                .pickerStyle(.segmented)
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
            Section("Workday") {
                Picker("Starts", selection: store.binding(\.settings.workdayStartMinutes)) {
                    ForEach(Self.halfHours, id: \.self) { Text(Format.minutesOfDay($0, style: store.state.settings.clockStyle)).tag($0) }
                }
                Picker("Ends", selection: store.binding(\.settings.workdayEndMinutes)) {
                    ForEach(Self.halfHours, id: \.self) { Text(Format.minutesOfDay($0, style: store.state.settings.clockStyle)).tag($0) }
                }
            }
            Section {
                Picker("When not in use", selection: store.binding(\.settings.restStyle)) {
                    Text("Stay full size").tag(RestStyle.full)
                    Text("Shrink, grow on hover").tag(RestStyle.mini)
                    Text("Tuck into the edge").tag(RestStyle.tucked)
                }
                Toggle("Hide the corner", isOn: store.binding(\.settings.hidden))
            } header: {
                Text("Getting it out of the way")
            } footer: {
                Text("Shrunk, it rests as a small quarter showing just the time and grows when the pointer reaches it. Tucked, it becomes a dot so the buttons under it stay clickable; push the pointer into the left edge of the screen, next to the dot, to bring it back. ⌃⌥C hides or shows it from anywhere.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Section("Corner") {
                Picker("Size", selection: store.binding(\.settings.cornerSize)) {
                    Text("Small").tag(CornerSize.small)
                    Text("Medium").tag(CornerSize.medium)
                    Text("Large").tag(CornerSize.large)
                }
                .pickerStyle(.segmented)
                Picker("Close the card after", selection: store.binding(\.settings.autoCollapseSeconds)) {
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("Never").tag(0)
                }
            }
            Section("Calendar") {
                Toggle("Show my next meeting", isOn: store.binding(\.settings.showMeetings))
                Picker("Alert me", selection: store.binding(\.settings.meetingAlertMinutes)) {
                    Text("When it starts").tag(0)
                    Text("1 minute before").tag(1)
                    Text("5 minutes before").tag(5)
                    Text("10 minutes before").tag(10)
                    Text("Never").tag(-1)
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
                    ForEach(store.calendars) { cal in
                        Toggle(isOn: Binding(
                            get: { !store.state.settings.excludedCalendarIDs.contains(cal.id) },
                            set: { _ in store.toggleCalendar(cal.id) }
                        )) {
                            HStack(spacing: 6) {
                                Circle().fill(Color(hex: cal.colorHex) ?? .accentColor).frame(width: 8, height: 8)
                                Text(cal.title)
                                Text(cal.source).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section {
                Toggle("Show Claude Code activity", isOn: store.binding(\.settings.showClaude))
                HStack {
                    Label(store.claudeHooksInstalled ? "Hooks are set up" : "Hooks aren't set up",
                          systemImage: store.claudeHooksInstalled ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(store.claudeHooksInstalled ? Color.green : Color.secondary)
                    Spacer()
                    Button(store.claudeHooksInstalled ? "Remove…" : "Set up…") {
                        store.claudeHooksInstalled ? removeClaude() : setUpClaude()
                    }
                }
            } header: {
                Text("Claude Code")
            } footer: {
                Text("Shows when a Claude Code session is working, needs you, or is done, in the CLI or the Claude app's Code tab. Set up adds small hooks to ~/.claude/settings.json; nothing leaves your Mac.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Section("Alerts") {
                Toggle("Play a chime", isOn: store.binding(\.settings.chime))
                Toggle("Show a notification", isOn: store.binding(\.settings.notify))
            }
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        LoginItem.set(on)
                        launchAtLogin = LoginItem.isEnabled
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
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
        HStack {
            Picker(title, selection: Binding(
                get: { zone.wrappedValue.id },
                set: { zone.wrappedValue = ZoneClock(id: $0, label: ZoneClock.defaultLabel(for: $0)) }
            )) {
                ForEach(Self.zones, id: \.self) { Text($0).tag($0) }
            }
            TextField("Label", text: zone.label)
                .frame(width: 64)
                .labelsHidden()
        }
    }
}
