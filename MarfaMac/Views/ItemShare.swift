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
        Self.show(fileURL.map { [$0] } ?? text.map { [$0] } ?? [], near: page)
    }

    /// Tells the person about missing links, then offers the rest to the picker, hung from the window Share was chosen in
    /// (`window`, taken when it was chosen): if that window closes while the links are read, nothing is shown.
    @MainActor static func presentLinks(of ids: [ItemID], in library: any ItemLibrary, near page: NSView?, from window: NSWindow?) async {
        guard let found = await library.links(of: ids) else { return }
        guard !found.links.isEmpty else {
            library.notices.tell(
                String(localized: "Can’t Share"),
                String(localized: "These items don’t have links yet. Try again once Marfa has finished syncing."))
            return
        }
        if found.missing > 0 {
            library.notices.tell(
                String(localized: "Some Links Not Shared"),
                String(localized: "\(found.missing) of the items don’t have a link yet, so only the others are shared."))
        }
        guard let window, window.isVisible || window.isMiniaturized else { return }
        show(found.links.map(\.url), near: page?.window === window ? page : nil, in: window)
    }

    private static func show(_ items: [Any], near page: NSView?, in window: NSWindow? = nil) {
        let anchor = page.flatMap { $0.window != nil ? $0 : nil } ?? (window ?? NSApp.keyWindow)?.contentView
        guard let anchor else { return }
        let bounds = anchor.bounds
        let rect = NSRect(x: bounds.midX - 1, y: anchor.isFlipped ? bounds.minY + 40 : bounds.maxY - 40, width: 2, height: 2)
        NSSharingServicePicker(items: items).show(relativeTo: rect, of: anchor, preferredEdge: anchor.isFlipped ? .maxY : .minY)
    }
}

/// The toolbar or menu can offer Share without observing each keystroke in the item's body.
struct ItemShareLink: View {
    var item: Item?
    var fileURL: URL?
    /// Nil while no library is open, which leaves Share disabled.
    var library: (any ItemLibrary)?
    /// The More menu shows titles alone, so its Share does too.
    var showsIcon = true
    /// Several chosen items, whose Share offers every one's link (`ItemShare.presentLinks`), in the order the window draws
    /// them. A link comes from the server, so a button reads it when it is chosen. Empty where one item or none is chosen.
    var chosen: Set<ItemID> = []
    var browser: Browser?

    var body: some View {
        if chosen.count > 1, let library, let browser {
            Button {
                let ids = browser.inListOrder(chosen, in: library)
                let window = NSApp.keyWindow
                Task { await ItemShare.presentLinks(of: ids, in: library, near: nil, from: window) }
            } label: { label }
        } else {
            single
        }
    }

    @ViewBuilder private var single: some View {
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
