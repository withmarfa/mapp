import SwiftUI

extension View {
    /// What the library asks of whoever is in front: to confirm erasing notes for good, and to hear of a change
    /// that could not be made. Every window carries these; the one in front takes each request as it comes, so it
    /// shows once, in a note's own window too, and stays until it is answered.
    func libraryDialogs() -> some View {
        modifier(LibraryDialogs())
    }
}

private struct LibraryDialogs: ViewModifier {
    @CurrentLibrary private var library
    @Environment(\.appearsActive) private var appearsActive
    @State private var purging: Set<ItemID> = []
    @State private var failure: Failure?

    private struct Failure {
        let title: String
        let message: String
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: library.notesToPurge, initial: true, take)
            .onChange(of: library.failure?.title, initial: true, take)
            .onChange(of: appearsActive, take)
            .confirmationDialog(
                "^[Delete \(purging.count) note](inflect: true) immediately?",
                isPresented: Binding { !purging.isEmpty } set: { if !$0 { purging = [] } }
            ) {
                Button("Delete", role: .destructive) { library.deletePermanently(purging) }
            } message: {
                Text("You can’t undo this action.")
            }
            .alert(
                failure?.title ?? "",
                isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } }
            ) {
            } message: {
                Text(failure?.message ?? "")
            }
    }

    /// The window in front takes what the library asks, which leaves the library's request answered for the rest.
    private func take() {
        guard appearsActive else { return }
        if !library.notesToPurge.isEmpty {
            purging = library.notesToPurge
            library.notesToPurge = []
        }
        if let asked = library.failure {
            failure = Failure(title: asked.title, message: asked.message)
            library.failure = nil
        }
    }
}
