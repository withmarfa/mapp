import AppKit
import SwiftUI

extension View {
    /// What the library asks of whoever is in front: to confirm erasing notes for good, and to hear of a change
    /// that could not be made. Every window carries these; the one in front takes each request as it comes, so it
    /// shows once, in a note's own window too, and stays until it is answered.
    func libraryDialogs() -> some View {
        modifier(LibraryDialogs())
    }

    /// Tells changes a library closed before keeping, in whichever window is in front, since the library that
    /// refused them is no longer shown anywhere. Their text goes to the clipboard as the person is told, so it
    /// outlives the alert.
    func unkeptChanges(_ libraries: Libraries) -> some View {
        modifier(UnkeptChanges(libraries: libraries))
    }
}

private struct UnkeptChanges: ViewModifier {
    let libraries: Libraries
    @Environment(\.appearsActive) private var appearsActive
    @State private var shown: Libraries.Unkept?

    func body(content: Content) -> some View {
        content
            .onChange(of: libraries.unkept, initial: true, take)
            .onChange(of: appearsActive, take)
            .alert(
                shown?.title ?? "",
                isPresented: Binding { shown != nil } set: { if !$0 { shown = nil } },
                presenting: shown
            ) { _ in
            } message: { unkept in
                Text(unkept.message)
            }
    }

    private func take() {
        guard appearsActive, let unkept = libraries.unkept else { return }
        libraries.unkept = nil
        if let text = unkept.text {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        shown = unkept
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
                Button("Delete", role: .destructive) { library.deletePermanentlyOnConfirm(purging) }
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
            // A library that cannot erase is never asked to.
            if library.capabilities.contains(.purge) { purging = library.notesToPurge }
            library.notesToPurge = []
        }
        if let asked = library.failure {
            failure = Failure(title: asked.title, message: asked.message)
            library.failure = nil
        }
    }
}
