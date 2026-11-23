import AppKit
import SwiftUI

/// What Share offers for one item: its file as itself where it has one, otherwise an item's markdown as text, the
/// form every destination can take. File > Share, More > Share and the palette's Share all read it from here.
struct ItemShare {
    var title = ""
    /// Nil when there is no one item to share.
    var text: String?
    var fileURL: URL?

    /// Nothing to share, where no library is open.
    init() {}

    init(item: Item?, fileURL: URL?, in library: any ItemLibrary) {
        title = item?.displayTitle ?? ""
        // A file is shared as itself. Reading the text here would follow a keystroke in whichever view built this.
        text = fileURL == nil ? item.flatMap { library.body(of: $0.id)?.text } : nil
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

/// Shares an item's markdown as text, the form every destination can take, or a file as itself.
/// The text is read in this view. A toolbar or menu that shows the control does not follow a keystroke.
struct ItemShareLink: View {
    var item: Item?
    var fileURL: URL?
    /// Nil while no library is open, which leaves Share disabled.
    var library: (any ItemLibrary)?
    /// The More menu shows titles alone, so its Share does too.
    var showsIcon = true

    var body: some View {
        let share = library.map { ItemShare(item: item, fileURL: fileURL, in: $0) } ?? ItemShare()
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
