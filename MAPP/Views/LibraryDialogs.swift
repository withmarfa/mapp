import AppKit
import Marfa
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
    /// outlives the alert; a later refusal adds to the alert and the clipboard until the person answers.
    func unkeptChanges(_ libraries: Libraries) -> some View {
        modifier(UnkeptChanges(libraries: libraries))
    }

    /// Warns, once, in whichever window is in front, that the server's address sends the key unencrypted.
    func plainHTTPNotice(_ host: MarfaHost) -> some View {
        modifier(PlainHTTPAlert(host: host))
    }
}

private struct PlainHTTPAlert: ViewModifier {
    let host: MarfaHost
    @Environment(\.appearsActive) private var appearsActive
    @State private var shown: PlainHTTPNotice?

    func body(content: Content) -> some View {
        content
            .onChange(of: host.plainHTTPNotice, initial: true, take)
            .onChange(of: appearsActive, take)
            .alert(
                Words.plainHTTPTitle,
                isPresented: Binding { shown != nil } set: { if !$0 { shown = nil } },
                presenting: shown
            ) { _ in
            } message: { notice in
                Text(Words.plainHTTP(origin: notice.origin))
            }
    }

    private func take() {
        guard appearsActive, let notice = host.plainHTTPNotice else { return }
        host.plainHTTPNotice = nil
        shown = notice
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
                isPresented: Binding { shown != nil } set: {
                    if !$0 {
                        shown = nil
                        libraries.unkept = nil
                    }
                },
                presenting: shown
            ) { _ in
            } message: { unkept in
                Text(unkept.message)
            }
    }

    private func take() {
        guard appearsActive, let unkept = libraries.unkept else { return }
        // Kept until the person has answered, so text refused while the alert is up is added to it and to the
        // clipboard rather than replacing what the first refusal left there.
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
            if library.canPurge { purging = library.notesToPurge }
            library.notesToPurge = []
        }
        if let asked = library.failure {
            failure = Failure(title: asked.title, message: asked.message)
            library.failure = nil
        }
    }
}
