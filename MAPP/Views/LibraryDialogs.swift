import AppKit
import SwiftUI

extension View {
    /// Asks whoever is in front to confirm erasing notes for good. Every window that shows a library carries this;
    /// the one in front takes each request as it comes, so it shows once, in a note's own window too.
    func libraryDialogs() -> some View {
        modifier(LibraryDialogs())
    }

    /// Tells the person, in whichever window is in front, each notice in the order it was told: something a library
    /// could not do, a change it could not keep, or an address that sends the key unencrypted. A notice carrying
    /// text the person typed puts it on the clipboard as they are told, so it outlives the alert.
    func notices(_ notices: Notices) -> some View {
        modifier(NoticeAlert(notices: notices))
    }
}

private struct NoticeAlert: ViewModifier {
    let notices: Notices
    @Environment(\.appearsActive) private var appearsActive
    @State private var shown: Notices.Notice?

    func body(content: Content) -> some View {
        content
            .onChange(of: notices.waiting.first, initial: true, take)
            .onChange(of: appearsActive, take)
            .alert(
                shown?.title ?? "",
                isPresented: Binding { shown != nil } set: {
                    if !$0, let shown {
                        notices.answered(shown)
                        self.shown = nil
                    }
                },
                presenting: shown
            ) { _ in
            } message: { notice in
                Text(notice.message)
            }
    }

    private func take() {
        guard appearsActive, let notice = notices.waiting.first else { return }
        // Changes not kept while the alert is up gather into the notice shown, so the clipboard gets all of their
        // text rather than only the last.
        if let text = notice.text, text != shown?.text {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        shown = notice
    }
}

private struct LibraryDialogs: ViewModifier {
    @CurrentLibrary private var library
    @Environment(\.appearsActive) private var appearsActive
    @State private var purging: Set<ItemID> = []

    func body(content: Content) -> some View {
        content
            .onChange(of: library.notesToPurge, initial: true, take)
            .onChange(of: appearsActive, take)
            .confirmationDialog(
                "^[Delete \(purging.count) note](inflect: true) immediately?",
                isPresented: Binding { !purging.isEmpty } set: { if !$0 { purging = [] } }
            ) {
                Button("Delete", role: .destructive) { library.deletePermanentlyOnConfirm(purging) }
            } message: {
                Text("You can’t undo this action.")
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
    }
}
