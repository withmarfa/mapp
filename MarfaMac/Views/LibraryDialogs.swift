import AppKit
import SwiftUI

extension View {
    /// Asks whoever is in front to confirm erasing items for good. Every window that shows a library carries this;
    /// the one in front takes each request as it comes, so it shows once, in an item's own window too.
    func libraryDialogs() -> some View {
        modifier(LibraryDialogs())
    }

    /// Asks the person to confirm moving several items to Recently Deleted, for the window whose presentation it is given.
    func deleteConfirmation(for details: DetailsPresentation) -> some View {
        modifier(DeleteConfirmation(details: details))
    }

    /// Tells the person, in one window in front, each notice in the order it was told: something a library could
    /// not do, a change it could not keep, or an address that sends the key unencrypted. A notice carrying text the
    /// person typed puts it on the clipboard as they are first told, so it outlives the alert. A notice that offers
    /// Settings asks `openSettings` to show the page, from the window the person answers in. One that saved files
    /// elsewhere offers to show them in the Finder.
    func notices(_ notices: Notices, openSettings: @escaping (SettingsPage) -> Void) -> some View {
        modifier(NoticeAlert(notices: notices, openSettings: openSettings))
    }
}

private struct NoticeAlert: ViewModifier {
    let notices: Notices
    let openSettings: (SettingsPage) -> Void
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
            ) { notice in
                // The fix is the default button, as in a system alert; a notice with none keeps the system's OK.
                if case .openSettings(let page) = notice.action {
                    Button("Open Settings…") { openSettings(page) }
                    Button("Not Now", role: .cancel) {}
                } else if case .showInFinder(let files) = notice.action {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(files) }
                    Button("Not Now", role: .cancel) {}
                }
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
            DeletionWords.moveTitle(count: details.deletion?.ids.count ?? 0),
            isPresented: Binding { details.deletion != nil } set: { if !$0 { details.deletion = nil } },
            presenting: details.deletion
        ) { request in
            Button("Move to Recently Deleted", role: .destructive) {
                Browser.moveToRecentlyDeleted(request.ids, in: library, undoManager: request.undoManager, toasts: details.toasts)
            }
        } message: { request in
            Text(DeletionWords.moveMessage(alsoTaking: request.alsoTaking))
        }
    }
}

private struct LibraryDialogs: ViewModifier {
    @CurrentLibrary private var library
    @Environment(\.appearsActive) private var appearsActive
    private struct Request {
        let library: any ItemLibrary
        let rows: [Item]
    }

    @State private var purging: Request?

    func body(content: Content) -> some View {
        content
            .onChange(of: library.itemsToPurge, initial: true, take)
            .onChange(of: appearsActive, take)
            .confirmationDialog(
                DeletionWords.purgeTitle(count: purging?.rows.count ?? 0),
                isPresented: Binding { purging != nil } set: { if !$0 { purging = nil } },
                presenting: purging
            ) { request in
                Button("Delete", role: .destructive) {
                    guard library === request.library else {
                        library.notices.tell(
                            String(localized: "Can’t Delete Immediately"),
                            String(localized: "The library whose Trash you opened is no longer open."))
                        return
                    }
                    library.purgeConfirmedRows(request.rows)
                }
            } message: { request in
                Text(DeletionWords.purgeMessage(count: request.rows.count))
            }
    }

    /// The window in front takes what the library asks, which leaves the library's request answered for the rest.
    private func take() {
        guard appearsActive else { return }
        if !library.itemsToPurge.isEmpty {
            // The server may have gone out of reach since the person asked.
            if library.reachesServer {
                let rows = library.itemsToPurge.compactMap { library.item($0) }.filter { $0.state == .trashed }
                if !rows.isEmpty { purging = Request(library: library, rows: rows) }
            } else {
                library.tellCannotPurge()
            }
            library.itemsToPurge = []
        }
    }
}
