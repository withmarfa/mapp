import AppKit
import SwiftUI

/// What Share offers for one item: its file as itself where it has one, otherwise a note's markdown as text, the
/// form every destination can take. File > Share, More > Share and the palette's Share all read it from here.
struct NoteShare {
    var title = ""
    /// Nil when there is no one note to share.
    var text: String?
    var fileURL: URL?

    /// Nothing to share, where no library is open.
    init() {}

    init(note: Item?, fileURL: URL?, in library: any ItemLibrary) {
        title = note?.title ?? ""
        text = note.flatMap { library.body(of: $0.id)?.text }
        self.fileURL = fileURL
    }

    var isAvailable: Bool { fileURL != nil || text != nil }

    /// Opens the system's share picker, for a place that has no Share button of its own to open it from. It
    /// hangs from the top of the page when one is showing, and from the top of the window otherwise.
    func present(near page: NSView?) {
        guard isAvailable else { return }
        let anchor = page.flatMap { $0.window != nil ? $0 : nil } ?? NSApp.keyWindow?.contentView
        guard let anchor else { return }
        let items: [Any] = fileURL.map { [$0] } ?? text.map { [$0] } ?? []
        let bounds = anchor.bounds
        let rect = NSRect(x: bounds.midX - 1, y: anchor.isFlipped ? bounds.minY + 40 : bounds.maxY - 40, width: 2, height: 2)
        NSSharingServicePicker(items: items).show(relativeTo: rect, of: anchor, preferredEdge: anchor.isFlipped ? .maxY : .minY)
    }
}

/// Shares a note's markdown as text, the form every destination can take, or a file as itself.
struct NoteShareLink: View {
    let share: NoteShare
    /// The More menu shows titles alone, so its Share does too.
    var showsIcon = true

    var body: some View {
        if let fileURL = share.fileURL {
            ShareLink(item: fileURL) { label }
        } else if let text = share.text {
            ShareLink(item: text, subject: Text(share.title), preview: SharePreview(share.title)) { label }
        } else {
            ShareLink(item: "") { label }
                .disabled(true)
        }
    }

    @ViewBuilder private var label: some View {
        if showsIcon {
            Label("Share…", systemImage: "square.and.arrow.up")
        } else {
            Text("Share…")
        }
    }
}
