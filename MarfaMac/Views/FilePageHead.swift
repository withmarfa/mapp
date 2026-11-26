import SwiftUI

/// What a file's viewer needs of the page's head, which is its first inset: the viewer keeps its own scroller, starts
/// its content below the toolbar and the head, and reports how far it has moved so the head, drawn over that space,
/// moves up with it (`ScrollingHeader`). Every kind of file page takes this the same way, so a later kind (audio, video)
/// is one more viewer that honors it.
struct FileHeadSpace {
    /// The toolbar's height, which the page runs under.
    var toolbar: CGFloat
    /// The height of the head's block: the notices and the head.
    var head: CGFloat
    /// The viewer has moved `offset` from its start.
    let scrolled: (CGFloat) -> Void

    /// How far the viewer's content starts below its top edge.
    var top: CGFloat { toolbar + head }
}

/// A file's head, as every item's: the kicker, the title, then the rows that have a value. The rows the item can take an
/// edit for open their editor here; the title is shown, not typed. A file's own facts (its size, its type) are not rows,
/// since the server owns them.
struct FilePageHead: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @AppStorage(InterfaceKey.textSize) private var interfaceTextSize = InterfaceStyle.defaultTextSize
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    @AppStorage(PagePlacements.key) private var placements = PagePlacements()
    @AppStorage(PageKey.titleLines) private var titleLines = TitleLines.standard
    @AppStorage(PageKey.showsCoordinates) private var showsCoordinates = false
    @AppStorage(PageKey.pinsProperties) private var pinsProperties = false
    @StoredPageStyle private var style
    let item: Item
    let inset: CGFloat
    let drafts: DetailsPresentation
    /// Shows the item a link in the head names.
    let open: (ItemID) -> Void

    var body: some View {
        let head = PageHead(
            of: item, in: library, placements: placements, pinsProperties: pinsProperties, dateFormat: dateFormat,
            showsCoordinates: showsCoordinates)
        let statusField = library.catalogue.itemTypes[item.type]?.statusField
        VStack(alignment: .leading, spacing: 0) {
            PageHeadView(item: item, head: head, statusField: statusField, drafts: drafts, open: open, edit: edit) {
                FileTitle(item: item, size: style.titleSize, lines: TitleLines.resolved(titleLines))
            }
            if let statusField, drafts.draft(for: item.id, key: statusField.key).rejected {
                Text("The value could not be saved.")
                    .font(InterfaceStyle.captionFont.scaled(by: InterfaceStyle.scale(for: interfaceTextSize)))
                    .foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, inset)
        .padding(.top, 16)
        .padding(.bottom, 12)
        // A refused status belongs to the visit, as the item page's does.
        .onChange(of: item.id) { old, _ in
            if let key = library.item(old).flatMap({ library.catalogue.itemTypes[$0.type]?.statusField?.key }) {
                drafts.draft(for: old, key: key).rejected = false
            }
        }
    }

    private func edit(_ row: PropertyRow, under view: NSView) {
        guard let request = ItemPageHeader.valueRequest(
            of: row.id, in: item.id, library: library, drafts: drafts, undoManager: undoManager, follow: open)
        else { return }
        ValueEditPresenter.shared.present(request, anchor: view)
    }
}

/// The title, as text: a file is renamed with Rename, as before, and its title is not typed in the head.
private struct FileTitle: View {
    let item: Item
    let size: CGFloat
    let lines: Int

    var body: some View {
        Text(verbatim: item.displayTitle)
            .lineLimit(lines)
            .truncationMode(.tail)
            .textSelection(.enabled)
            .font(.system(size: size, weight: .semibold))
            .tracking(size * Typography.titleTracking)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("FileTitle")
    }
}
