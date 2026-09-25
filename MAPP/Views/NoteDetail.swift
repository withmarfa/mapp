import SwiftUI

struct NoteDetail: View {
    @Environment(NoteLibrary.self) private var library
    let browser: Browser
    var pane: FocusState<Browser.Pane?>.Binding

    var body: some View {
        let notes = browser.selection.compactMap { library.note($0) }
        if notes.count > 1 {
            ContentUnavailableView("^[\(notes.count) note](inflect: true) selected", systemImage: "note.text")
        } else if let note = notes.first {
            NotePage(note: note)
                .focused(pane, equals: .page)
                // Escape hands the keyboard back to the list, as in Mail.
                .onExitCommand { pane.wrappedValue = .list }
                .onAppear(perform: grantFocusRequest)
                .onChange(of: browser.focusRequest, grantFocusRequest)
                .id(note.id)
        } else {
            ContentUnavailableView("No Note Selected", systemImage: "note.text")
        }
    }

    private func grantFocusRequest() {
        guard browser.focusRequest == .page else { return }
        pane.wrappedValue = .page
        browser.focusRequest = nil
    }
}

/// One note as a page. Until the formatted editor arrives, the markdown is edited as plain text.
struct NotePage: View {
    @Environment(NoteLibrary.self) private var library
    let note: Note

    var body: some View {
        TextEditor(text: Binding(
            get: { library.note(note.id)?.body ?? "" },
            set: { library.updateBody(of: note.id, to: $0) }
        ))
        .font(.body)
        .accessibilityIdentifier("NoteEditor")
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .disabled(note.isDeleted)
        .safeAreaInset(edge: .top, spacing: 0) {
            if note.isDeleted {
                DeletedNoteBanner(id: note.id)
            }
        }
    }
}

/// Deleted notes cannot be edited; this says so and offers the way back, as Notes does.
private struct DeletedNoteBanner: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    let id: Note.ID

    var body: some View {
        HStack {
            Text("Recently deleted notes can’t be edited.")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Recover") { library.recover([id], undoManager: undoManager) }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
