import AppKit
import SwiftUI

extension View {
    /// Asks whoever is in front to confirm erasing notes for good. Every window that shows a library carries this;
    /// the one in front takes each request as it comes, so it shows once, in a note's own window too.
    func libraryDialogs() -> some View {
        modifier(LibraryDialogs())
    }

    /// Asks the person to confirm moving several items to Recently Deleted, for the window whose presentation it is given.
    func deleteConfirmation(for details: DetailsPresentation) -> some View {
        modifier(DeleteConfirmation(details: details))
    }

    /// Tells the person, in one window in front, each notice in the order it was told: something a library could
    /// not do, a change it could not keep, or an address that sends the key unencrypted. A notice carrying text the
    /// person typed puts it on the clipboard as they are first told, so it outlives the alert.
    func notices(_ notices: Notices) -> some View {
        modifier(NoticeAlert(notices: notices))
    }
}

private struct NoticeAlert: ViewModifier {
    let notices: Notices
    @Environment(\.appearsActive) private var appearsActive
    @State private var window = UUID()
    @State private var shown: Notices.Notice?

    func body(content: Content) -> some View {
        content
            .onChange(of: notices.waiting.first?.id, initial: true, take)
            .onChange(of: notices.shownIn, take)
            .onChange(of: appearsActive, take)
            .onDisappear {
                shown = nil
                notices.released(by: window)
            }
            .alert(
                shown?.title ?? "",
                isPresented: Binding { shown != nil } set: {
                    if !$0, let shown {
                        self.shown = nil
                        notices.answered(shown.id)
                    }
                },
                presenting: shown
            ) { _ in
            } message: { notice in
                Text(notice.message)
            }
    }

    private func take() {
        guard appearsActive, shown == nil else { return }
        shown = notices.show(in: window, copying: Notices.copyToClipboard)
    }
}

extension Notices {
    /// Where a notice puts the text the person typed, for them to paste back.
    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct DeleteConfirmation: ViewModifier {
    @CurrentLibrary private var library
    let details: DetailsPresentation

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "^[Move \(details.deletion?.ids.count ?? 0) item](inflect: true) to Recently Deleted?",
            isPresented: Binding { details.deletion != nil } set: { if !$0 { details.deletion = nil } },
            presenting: details.deletion
        ) { request in
            Button("Move to Recently Deleted", role: .destructive) {
                library.delete(request.ids, undoManager: request.undoManager)
            }
        } message: { _ in
            Text("You can bring them back from Recently Deleted.")
        }
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
