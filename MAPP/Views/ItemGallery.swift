import AppKit
import SwiftUI

struct ItemGallery: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    @Environment(\.interfaceTextSize) private var textSize
    @Bindable var browser: Browser
    let order: ItemOrder
    var pane: FocusState<Browser.Pane?>.Binding
    @State private var width: CGFloat = 900
    @State private var height: CGFloat = 600
    @State private var anchor: ItemID?
    @State private var cursor: ItemID?
    @State private var daysSeen = 0
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    /// What each card says, worked out once for each item from its type's look.
    @State private var cardContents = CardContents()

    private static let spacing: CGFloat = 16
    private static let inset: CGFloat = 24

    /// What the view chose for its cards and the grid it makes: a larger card means fewer columns across the same width.
    private struct Plan {
        let cards: ViewCards
        let columns: Int
        let thumbnailWidth: CGFloat
        let contents: [ItemID: RowContent]
        /// Each item's attached files, read once here so no card reads the library's links.
        let attachments: [ItemID: [Item]]
    }

    private func plan(for cards: ViewCards, contents: [ItemID: RowContent], attachments: [ItemID: [Item]]) -> Plan {
        let columns = max(1, Int((width - 2 * Self.inset + Self.spacing) / (cards.size.columnWidth * InterfaceStyle.scale(for: textSize) + Self.spacing)))
        return Plan(cards: cards, columns: columns, thumbnailWidth: (width - 2 * Self.inset - CGFloat(columns - 1) * Self.spacing) / CGFloat(columns), contents: contents,
            attachments: attachments)
    }

    var body: some View {
        let _ = daysSeen
        let sections = browser.sections(in: library, order: order, now: library.now())
        let ids = Cost.measure(.galleryBody) { sections.flatMap { $0.items.map(\.id) } }
        let title = browser.isSearching ? String(localized: "Search") : library.name(of: browser.item)
        // The picture's opening lines are drawn on the card when the preview allows them, so the line under the title
        // does not say them again.
        let shape = CardShape(dropsOpening: browser.cards.preview == .pictureOrText || browser.cards.preview == .text)
        let list = RowList(date: .look, format: dateFormat, day: Calendar.current.startOfDay(for: library.now()))
        let contents = cardContents.contents(of: sections.flatMap(\.items), in: library, looks: browser.looks(in: library), list: list, shape: shape)
        let attachments = CardAttachments.of(sections.flatMap(\.items), in: library, showsPicture: browser.cards.preview.showsPicture)
        keyboardCollection(sections, ids: ids, plan: plan(for: browser.cards, contents: contents, attachments: attachments))
        .searchStatus(browser)
        .accessibilityLabel(title)
        .onChange(of: browser.isSearchExpanded) {
            if !browser.isSearchExpanded { browser.focusRequest = .list }
        }
        .onChange(of: ids) { _, new in
            if let cursor, !new.contains(cursor) { self.cursor = nil }
            if let anchor, !new.contains(anchor) { self.anchor = nil }
        }
        .overlay {
            if ids.isEmpty {
                if browser.isSearching {
                    SearchEmptyState(browser: browser)
                        .accessibilityIdentifier("GalleryEmptySearch")
                } else { EmptyState(browser.item == .files ? "No Files" : "No Items") }
            }
        }
        .filteredEmptyState(browser)
        .navigationTitle(title)
        .navigationSubtitle(
            (browser.isSearching ? Text("^[\(ids.count) result](inflect: true)") : Text("^[\(ids.count) item](inflect: true)"))
                .editedSubtitle(browser.hasViewChanges))
        .toolbar(removing: browser.isSearchExpanded ? .title : nil)
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) { daysSeen += 1 }
        }
        .dragContainer(for: ItemReference.self) { ids in ids.map(library.dragReference(of:)) }
        .dragsSelection(of: browser)
    }

    private func collection(_ sections: [ItemSection], ids: [ItemID], plan: Plan) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(sections) { section in
                        sectionGrid(section, ids: ids, plan: plan)
                    }
                }
                .padding(Self.inset)
                .remembersScroll(in: browser.listMemory)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Items")
                // Space between and below the cards clears the selection, as a click on a Finder window's does.
                .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
                .background {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture {
                            browser.selection = []
                            anchor = nil
                            pane.wrappedValue = .list
                        }
                }
            }
            .bandsToolbar()
            .focusable()
            .focusEffectDisabled()
            .focused(pane, equals: .list)
            .accessibilityLabel(browser.isSearching ? String(localized: "Search") : library.name(of: browser.item))
            .accessibilityIdentifier("ItemGallery")
            .onAppear {
                if let selected = ids.first(where: browser.selection.contains) { proxy.scrollTo(selected) }
            }
            .onChange(of: cursor) { if let cursor { proxy.scrollTo(cursor) } }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            if size.width.isFinite, size.width > 0 { width = size.width }
            if size.height.isFinite, size.height > 0 { height = size.height }
        }
    }

    private func sectionGrid(_ section: ItemSection, ids: [ItemID], plan: Plan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let group = section.group {
                Text(group.title())
                    .interfaceFont(.body.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing, alignment: .top), count: plan.columns), spacing: Self.spacing + 4) {
                ForEach(section.items) { item in
                    if let content = plan.contents[item.id] { card(item, content: content, ids: ids, plan: plan).id(item.id) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(section.group?.title() ?? String(localized: "Items"))
        }
    }

    private func keyboardCollection(_ sections: [ItemSection], ids: [ItemID], plan: Plan) -> some View {
        collection(sections, ids: ids, plan: plan)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: .down) { key in
            let current = cursor ?? ids.first(where: browser.selection.contains)
            let destination: ItemID?
            if key.key == .upArrow || key.key == .downArrow {
                destination = GallerySelection.movingVertically(from: current, sections: sections.map { $0.items.map(\.id) }, columns: plan.columns, down: key.key == .downArrow)
            } else {
                destination = GallerySelection.moving(from: current, among: ids, by: key.key == .leftArrow ? -1 : 1)
            }
            guard let next = destination else { return .ignored }
            select(next, ids: ids, extending: key.modifiers.contains(.shift), toggling: false)
            return .handled
        }
        .quickLooksOnSpace(browser)
        .onKeyPress(.return) {
            browser.openSelection() ? .handled : .ignored
        }
        .onKeyPress(.escape) {
            browser.selection = []
            return .handled
        }
        .onKeyPress("a", phases: .down) { key in
            guard key.modifiers.contains(.command) else { return .ignored }
            browser.selection = Set(ids)
            return .handled
        }
        .onKeyPress(.delete, phases: .down) { key in
            guard key.modifiers.contains(.command), !browser.selection.isEmpty else { return .ignored }
            deleteSelection()
            return .handled
        }
        .onDeleteCommand(perform: deleteSelection)
        // AppKit maps Command-Backspace to this text-system command before keyDown reaches SwiftUI.
        .onCommand(#selector(NSResponder.deleteToBeginningOfLine(_:)), perform: deleteSelection)
    }

    private func card(_ item: Item, content: RowContent, ids: [ItemID], plan: Plan) -> some View {
        GalleryCell(
            item: item, browser: browser, order: order, width: plan.thumbnailWidth, cards: plan.cards,
            content: content, attachments: plan.attachments[item.id] ?? [], pane: pane,
            select: { id, extending, toggling in select(id, ids: ids, extending: extending, toggling: toggling) })
    }

    private func select(_ id: ItemID, ids: [ItemID], extending: Bool, toggling: Bool) {
        if anchor == nil { anchor = ids.first(where: browser.selection.contains) }
        browser.selection = GallerySelection.selecting(id, among: ids, current: browser.selection, anchor: anchor, extending: extending, toggling: toggling)
        if !extending { anchor = id }
        cursor = id
    }

    private func deleteSelection() {
        let ids = browser.selection
        library.deleteAfterSaving(ids, undoManager: undoManager, asking: details)
    }
}

/// One card of the gallery as a control: it answers a click, a double click, the context menu and a drag, and
/// reads the selection itself, so a selection that moves runs the bodies of the cells and of no card.
private struct GalleryCell: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    let item: Item
    let browser: Browser
    let order: ItemOrder
    let width: CGFloat
    let cards: ViewCards
    let content: RowContent
    let attachments: [Item]
    var pane: FocusState<Browser.Pane?>.Binding
    let select: (ItemID, _ extending: Bool, _ toggling: Bool) -> Void

    var body: some View {
        let isSelected = browser.selection.contains(item.id)
        Button {
            // SwiftUI Button actions do not expose the click's modifiers; AppKit supplies just that event.
            let modifiers = NSApp.currentEvent?.modifierFlags ?? []
            select(item.id, modifiers.contains(.shift), modifiers.contains(.command))
            pane.wrappedValue = .list
        } label: {
            GalleryCard(item: item, browser: browser, width: width, cards: cards, content: content, attachments: attachments)
                .equatable()
        }
        .buttonStyle(.plain)
        .focusable(false)
        .wantsCounts(of: item.id, content.countQueries, in: library.counts)
        .contentShape([.interaction, .accessibility], .rect(cornerRadius: 10))
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            browser.open([item.id])
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.displayTitle)
        .accessibilityValue(isSelected ? Text("Selected") : Text(""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("GalleryItem-\(item.id.rawValue)")
        .accessibilityAction {
            select(item.id, false, false)
            pane.wrappedValue = .list
        }
        .accessibilityAction(named: Text("Open")) {
            browser.open([item.id])
        }
        .contextMenu {
            ItemRowMenu(browser: browser, ids: browser.selection.contains(item.id) ? browser.selection : [item.id], undoManager: undoManager)
        }
        .draggable(containerItemID: item.id)
        .dropsInto(collection: library.catalogue.isCollection(item.type) ? item.id : nil, browser: browser, order: order)
    }
}
