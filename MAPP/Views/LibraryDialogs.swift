import SwiftUI

extension View {
    /// What the library asks of whoever is in front: to confirm erasing notes for good, and to hear of a change
    /// that could not be made. Every window carries these, and only the one in front shows them, so they show
    /// once, and in a note's own window too.
    func libraryDialogs() -> some View {
        modifier(LibraryDialogs())
    }
}

private struct LibraryDialogs: ViewModifier {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.appearsActive) private var appearsActive

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "^[Delete \(library.notesToPurge.count) note](inflect: true) immediately?",
                isPresented: Binding { appearsActive && !library.notesToPurge.isEmpty } set: { if !$0 { library.notesToPurge = [] } }
            ) {
                Button("Delete", role: .destructive) { library.deletePermanently(library.notesToPurge) }
            } message: {
                Text("You can’t undo this action.")
            }
            .alert(
                library.failure?.title ?? "",
                isPresented: Binding { appearsActive && library.failure != nil } set: { if !$0 { library.failure = nil } }
            ) {
            } message: {
                Text(library.failure?.message ?? "")
            }
    }
}
