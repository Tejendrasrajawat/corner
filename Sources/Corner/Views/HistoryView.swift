import AppKit
import CornerKit
import SwiftUI

/// Every to-do ever added, grouped by the day it was added: open ones, done ones, and ones
/// cleared off the card.
struct HistoryView: View {
    @ObservedObject var store: Store
    /// Snapshots can't draw a ScrollView, so they lay the list out flat.
    var flat = false
    @State private var filter = TodoFilter.all
    @State private var search = ""

    var body: some View {
        let groups = store.state.todoHistory(filter: filter, search: search, calendar: .current)
        let all = store.state.todos
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Show", selection: $filter) {
                    Text("All").tag(TodoFilter.all)
                    Text("Open").tag(TodoFilter.open)
                    Text("Done").tag(TodoFilter.done)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
                Spacer()
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            .padding(12)
            Divider()
            if groups.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checklist").font(.system(size: 28)).foregroundStyle(.tertiary)
                    Text(all.isEmpty ? "No to-dos yet" : "Nothing matches")
                        .font(.system(size: 14, weight: .medium))
                    Text(all.isEmpty ? "Type anything in Add (⌥⌘T) and it lands here too." : "Try another filter or search.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if flat {
                list(groups)
                Spacer(minLength: 0)
            } else {
                ScrollView { list(groups) }
            }
            Divider()
            HStack {
                let done = all.filter(\.isDone).count
                Text("\(all.count - done) open · \(done) done")
                Spacer()
                Text("Right-click a to-do for more")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 460, minHeight: 440)
        // Colors only: this is an ordinary window, so a solid theme's dark text would be unreadable here.
        .environment(\.theme, Theme.named(store.state.settings.theme))
        .tint(Theme.named(store.state.settings.theme).accent)
    }

    private func list(_ groups: [TodoDay]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(groups, id: \.day) { group in
                Text(dayTitle(group.day))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
                ForEach(group.todos) { HistoryRow(todo: $0, store: store) }
            }
        }
        .padding(.bottom, 12)
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return Format.shortDate(day, in: .current)
    }
}

struct HistoryRow: View {
    let todo: Todo
    let store: Store
    @Environment(\.theme) private var theme

    var body: some View {
        let added = Format.time(todo.createdAt, in: .current, style: store.state.settings.clockStyle)
        HStack(spacing: 8) {
            Button { store.toggleTodo(todo.id) } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(todo.isDone ? theme.todo : Color.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.isDone ? "Mark not done" : "Mark done")
            Text(todo.text)
                .strikethrough(todo.isDone)
                .foregroundStyle(todo.isDone ? Color.secondary : Color.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !todo.isOnCard {
                Text("Cleared")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .foregroundStyle(.secondary)
            }
            Text(todo.doneAt.map { "Added \(added) · Done \(doneText($0))" } ?? "Added \(added)")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .contextMenu {
            if !todo.isOnCard {
                Button("Put back on the card") { store.restoreTodo(todo.id) }
            }
            Button("Copy text") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(todo.text, forType: .string)
            }
            Divider()
            Button("Delete for good", role: .destructive) { store.deleteTodo(todo.id) }
        }
    }

    /// Just the time when it was done the same day it was added, otherwise the date too.
    private func doneText(_ done: Date) -> String {
        let time = Format.time(done, in: .current, style: store.state.settings.clockStyle)
        if Calendar.current.isDate(done, inSameDayAs: todo.createdAt) { return time }
        return "\(Format.shortDate(done, in: .current)) \(time)"
    }
}

@MainActor
final class HistoryWindowController {
    private let store: Store
    private var window: NSWindow?

    init(store: Store) {
        self.store = store
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            w.title = "To-do history"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: HistoryView(store: store))
            w.setFrameAutosaveName("CornerTodoHistory")
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
