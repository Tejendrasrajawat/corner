import Foundation

/// A to-do from quick add. Nothing is ever thrown away by ticking or clearing; the card shows
/// today's list and the history window shows all of it.
public struct Todo: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    public var createdAt: Date
    public var doneAt: Date?
    /// Taken off the card ("Clear done", or done on an earlier day) but kept in history.
    public var clearedAt: Date?

    public init(id: UUID = UUID(), text: String, createdAt: Date) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }

    public var isDone: Bool { doneAt != nil }
    public var isOnCard: Bool { clearedAt == nil }
}

public enum TodoFilter: String, CaseIterable, Sendable {
    case all, open, done
}

/// One day's section in the history window.
public struct TodoDay: Equatable, Sendable {
    public var day: Date
    public var todos: [Todo]
}

extension AppState {
    /// The card's list: open to-dos in the order you added them, then ticked ones in the order ticked.
    public var cardTodos: [Todo] {
        let onCard = todos.filter(\.isOnCard)
        let done = onCard.filter(\.isDone).sorted { ($0.doneAt ?? .distantPast) < ($1.doneAt ?? .distantPast) }
        return onCard.filter { !$0.isDone } + done
    }

    public mutating func addTodo(_ text: String, at now: Date) {
        todos.append(Todo(text: text, createdAt: now))
    }

    /// Unticking a to-do that had already left the card puts it back there, since it's open again.
    public mutating func toggleTodo(_ id: UUID, at now: Date) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        if todos[i].isDone {
            todos[i].doneAt = nil
            todos[i].clearedAt = nil
        } else {
            todos[i].doneAt = now
        }
    }

    /// Empty text deletes it.
    public mutating func editTodo(_ id: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        if trimmed.isEmpty {
            todos.remove(at: i)
        } else {
            todos[i].text = trimmed
        }
    }

    public mutating func deleteTodo(_ id: UUID) {
        todos.removeAll { $0.id == id }
    }

    public mutating func restoreTodo(_ id: UUID) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].clearedAt = nil
    }

    /// Takes ticked to-dos off the card; they stay in history.
    public mutating func clearDoneTodos(at now: Date) {
        for i in todos.indices where todos[i].isDone && todos[i].isOnCard {
            todos[i].clearedAt = now
        }
    }

    /// Moves an open to-do past its open neighbour on the card. -1 is up.
    public mutating func moveTodo(_ id: UUID, by offset: Int) {
        let open = todos.indices.filter { !todos[$0].isDone && todos[$0].isOnCard }
        guard let position = open.firstIndex(where: { todos[$0].id == id }) else { return }
        let target = position + offset
        guard open.indices.contains(target) else { return }
        todos.swapAt(open[position], open[target])
    }

    /// Ticked on an earlier day: off the card, so each morning starts with only what's still open.
    mutating func clearOldDoneTodos(at now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        for i in todos.indices where todos[i].isOnCard {
            if let done = todos[i].doneAt, done < today { todos[i].clearedAt = now }
        }
    }

    /// Every to-do, grouped by the day it was added, newest day first.
    public func todoHistory(filter: TodoFilter, search: String, calendar: Calendar) -> [TodoDay] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        func matches(_ t: Todo) -> Bool {
            let status: Bool
            switch filter {
            case .all: status = true
            case .open: status = !t.isDone
            case .done: status = t.isDone
            }
            return status && (query.isEmpty || t.text.lowercased().contains(query))
        }
        let grouped = Dictionary(grouping: todos.filter(matches)) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            TodoDay(day: day, todos: grouped[day, default: []].sorted { $0.createdAt < $1.createdAt })
        }
    }
}
