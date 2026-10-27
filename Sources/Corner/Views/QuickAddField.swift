import CornerKit
import SwiftUI

struct QuickAddField: View {
    @ObservedObject var store: Store
    @ObservedObject var ui: UIModel
    @State private var text = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("25m focus, fri 6pm release, buy milk", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(submit)
                .onChange(of: text) { error = nil }
            Text(error ?? preview ?? "A length makes a timer, a time makes a countdown, anything else a to-do")
                .font(.system(size: 11))
                .foregroundStyle(error == nil ? Color.secondary : Color.red)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            // The panel only becomes key after this view is on screen.
            DispatchQueue.main.async { focused = true }
        }
    }

    private var preview: String? {
        guard case .success(let entry) = QuickParse.parse(text, now: store.now) else { return nil }
        return QuickParse.describe(entry, now: store.now, style: store.state.settings.clockStyle)
    }

    private func submit() {
        switch QuickParse.parse(text, now: Date()) {
        case .success(let entry):
            store.add(entry)
            text = ""
            ui.endQuickAdd()
        case .failure(let e):
            error = e.message
        }
    }
}
