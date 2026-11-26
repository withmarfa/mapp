import SwiftUI

/// The field a new item's title is typed in where it will stand (`InPlaceRow`): Return adds it and starts the next,
/// Escape drops an empty row and keeps a typed one, and leaving the field adds what it holds.
struct InPlaceField: View {
    let browser: Browser
    let library: any ItemLibrary
    let undoManager: UndoManager?
    var prompt: LocalizedStringKey = "New"
    @FocusState private var isFocused: Bool

    var body: some View {
        let row = browser.inPlace
        VStack(alignment: .leading, spacing: 2) {
            TextField(prompt, text: Binding { row.draft?.title ?? "" } set: { title in row.change { $0.title = title } })
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { add(next: true) }
                .onKeyPress(.escape) {
                    browser.escapeInPlace()
                    return .handled
                }
                .accessibilityLabel(Text("New Item"))
                .accessibilityIdentifier("InPlaceField")
            if let notice = row.notice {
                Text(notice)
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: row.isEditing, initial: true) { _, editing in isFocused = editing }
        .onChange(of: isFocused) { _, focused in
            if focused {
                row.isEditing = true
            } else if row.isEditing {
                // Leaving the row adds it, as Return does, and ends it.
                row.isEditing = false
                add(next: false)
            }
        }
    }

    private func add(next: Bool) {
        Task { await browser.addInPlace(in: library, undoManager: undoManager, next: next) }
    }
}

/// The table's last row: New, which takes the caret on a click or ⌘N, or the row being typed, or one Escape left typed.
struct InPlaceTableRow: View {
    let browser: Browser
    let library: any ItemLibrary
    let undoManager: UndoManager?

    var body: some View {
        let row = browser.inPlace
        let isHere = row.place == browser.shown && row.spot?.layout == "table" && row.draft != nil
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .imageScale(.small)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            if isHere {
                InPlaceField(browser: browser, library: library, undoManager: undoManager)
            } else {
                Button {
                    browser.beginInPlace(in: library)
                } label: {
                    Text("New")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!QuickAdd.isAvailable(in: library))
                .accessibilityLabel(Text("New Item"))
                .accessibilityIdentifier("InPlaceNew")
            }
        }
        .interfaceFont(.body)
        .tableCellRoom()
    }
}

/// A new card at the top of a board's lane, typed where it will stand.
struct InPlaceCard: View {
    let browser: Browser
    let library: any ItemLibrary
    let undoManager: UndoManager?

    var body: some View {
        InPlaceField(browser: browser, library: library, undoManager: undoManager)
            .interfaceFont(.body.weight(.medium))
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.18), lineWidth: 1) }
    }
}

/// A block dragged on the calendar's week, typed where it will stand, with the time it holds under its title.
struct InPlaceBlock: View {
    let browser: Browser
    let library: any ItemLibrary
    let undoManager: UndoManager?
    let start: Date
    let end: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            InPlaceField(browser: browser, library: library, undoManager: undoManager, prompt: "New Item")
                .interfaceFont(.caption.weight(.semibold))
            Text("\(start.formatted(date: .omitted, time: .shortened)) to \(end.formatted(date: .omitted, time: .shortened))")
                .interfaceFont(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.14), in: .rect(cornerRadius: 4))
    }
}
