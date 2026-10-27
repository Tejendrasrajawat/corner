import CornerKit
import SwiftUI

/// The card's to-do list: open items in the order added, ticked ones greyed out underneath.
struct TodoSection: View {
    @ObservedObject var store: Store
    @ObservedObject var ui: UIModel
    @Environment(\.theme) private var theme

    /// Rows past this many scroll, so a long list can't push the card off the screen.
    private static let visibleRows = 8

    var body: some View {
        let items = store.state.cardTodos
        let open = items.filter { !$0.isDone }.count
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checklist").foregroundStyle(theme.isPlain ? Color.secondary : theme.todo).frame(width: 16)
                Text(open == 0 ? "To-dos" : "To-dos · \(open)")
                Spacer()
                if items.contains(where: \.isDone) {
                    Chip(title: "Clear done") { store.clearDoneTodos() }
                }
                IconButton(symbol: "clock.arrow.circlepath", help: "To-do history") { ui.openHistory() }
            }
            .font(.system(size: 13))
            if items.isEmpty {
                Text("Type anything in Add (⌥⌘T) to make a to-do.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 22)
            } else if items.count > Self.visibleRows {
                ScrollView { rows(items) }
                    .frame(height: CGFloat(Self.visibleRows) * TodoRow.height)
            } else {
                rows(items)
            }
        }
    }

    private func rows(_ items: [Todo]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { TodoRow(todo: $0, store: store, ui: ui) }
        }
    }
}

struct TodoRow: View {
    static let height: CGFloat = 24

    let todo: Todo
    let store: Store
    @ObservedObject var ui: UIModel
    @Environment(\.theme) private var theme
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Button { store.toggleTodo(todo.id) } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(todo.isDone ? theme.todo : Color.secondary)
                    .frame(width: 16, height: Self.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.isDone ? "Mark not done" : "Mark done")
            if ui.editingTodo == todo.id {
                TextField("To-do", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(save)
                    .onAppear {
                        draft = todo.text
                        DispatchQueue.main.async { focused = true }
                    }
            } else {
                Text(todo.text)
                    .lineLimit(1)
                    .strikethrough(todo.isDone)
                    .foregroundStyle(todo.isDone ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { ui.editTodo(todo.id) }
                    .help(todo.text)
            }
        }
        .font(.system(size: 13))
        .frame(height: Self.height)
        .contextMenu {
            Button("Edit") { ui.editTodo(todo.id) }
            if !todo.isDone {
                Button("Move up") { store.moveTodo(todo.id, by: -1) }
                Button("Move down") { store.moveTodo(todo.id, by: 1) }
            }
            Divider()
            Button("Delete", role: .destructive) { store.deleteTodo(todo.id) }
        }
    }

    private func save() {
        store.editTodo(todo.id, text: draft)
        ui.endEditing()
    }
}
