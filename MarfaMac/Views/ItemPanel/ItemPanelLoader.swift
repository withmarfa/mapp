import SwiftUI

/// Makes the panel for one item: reads what its parts show and works out, away from the main thread, what the text and the
/// file need (Reading Time, Words, a PDF's pages and contents). The host remakes it for another item.
struct ItemPanelLoader<Legacy: View>: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    let item: Item
    let relationships: [ItemRelationship]
    let mentions: [ItemRelationshipTarget]
    let editor: EditorController?
    let details: DetailsPresentation
    let onOpen: (ItemID) -> Void
    @ViewBuilder let legacy: Legacy
    @State private var textFacts: PanelTextFacts?
    @State private var pdf: PanelPDFFacts?

    private var isPDF: Bool { item.fileType.flatMap(FileViewKind.of) == .pdf }

    /// Counting waits for the page to settle, so typing in a long document does not count every keystroke.
    private struct CountKey: Hashable {
        let item: ItemID
        let revision: Int
        let hasHeadings: Bool
    }

    var body: some View {
        let id = item.id
        let headings = item.isFile ? [] : (editor?.headings(of: id) ?? [])
        ItemPanel(
            item: item,
            outline: PanelOutlineModel(headings: headings, text: textFacts, pdf: pdf, isPDF: isPDF),
            links: PanelLinks.groups(of: item, in: library, relationships: relationships, mentions: mentions, format: dateFormat),
            info: PanelInfoModel(
                item: item, source: item.source.map { library.sources.info($0).name },
                version: library.itemVersion(id) ?? item.version, pages: pdf?.pages, moves: moves,
                move: { library.perform($0 == .library ? .keep : .moveToFeed, on: [id], undoManager: undoManager, details: details) },
                leavesTheFeed: item.tier == .feed && item.state == .active ? library.catalogue.feedExpiry(of: item) : nil),
            onOpen: onOpen,
            onHeading: { editor?.revealHeading(at: $0) },
            onPage: goToPage,
            onShowHistory: { details.showHistory(of: id, in: library) }
        ) { legacy }
        .task(id: CountKey(item: id, revision: library.contentRevision, hasHeadings: !headings.isEmpty)) {
            await count(hasHeadings: !headings.isEmpty)
        }
        .task(id: id) { await readPDF() }
    }

    /// The tiers the item may move to now: the other one, where the item allows it and the type may be there. Nil where it
    /// may not move, so Info states the tier and offers no menu.
    private var moves: Set<Tier>? {
        guard item.allows(.tier) else { return nil }
        let offered = library.selectionCommands([item.id])
        var tiers: Set<Tier> = []
        if offered.contains(.keep) { tiers.insert(.library) }
        if offered.contains(.moveToFeed) { tiers.insert(.feed) }
        return tiers.isEmpty ? nil : tiers
    }

    private func count(hasHeadings: Bool) async {
        guard hasHeadings, !item.isFile, let text = library.bodyText(item.id) else {
            textFacts = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        textFacts = await Task.detached(priority: .utility) { PanelTextFacts.count(text) }.value
    }

    private func readPDF() async {
        guard isPDF, let url = try? await library.fileURL(of: item.id) else {
            pdf = nil
            return
        }
        pdf = await Task.detached(priority: .utility) { PanelPDFFacts.read(url) }.value
    }

    /// Scrolls the PDF on the page to a page of its contents, and tells the corner which page it reached.
    private func goToPage(_ page: Int) {
        guard let viewing = details.fileViewing(of: item.id), let reached = viewing.showPage?(page), let pages = viewing.pages else { return }
        viewing.reportPages(count: pages.count, current: reached)
    }
}
