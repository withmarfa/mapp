import AppKit
import SwiftUI

struct ItemGallery: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.interfaceTextSize) private var textSize
    @Bindable var browser: Browser
    let order: NoteOrder
    var pane: FocusState<Browser.Pane?>.Binding
    @State private var width: CGFloat = 900
    @State private var height: CGFloat = 600
    @State private var anchor: ItemID?
    @State private var cursor: ItemID?
    @State private var daysSeen = 0

    private static let spacing: CGFloat = 20
    private static let inset: CGFloat = 24

    private var columnCount: Int {
        max(1, Int((width - 2 * Self.inset + Self.spacing) / (190 * InterfaceStyle.scale(for: textSize) + Self.spacing)))
    }

    private var thumbnailWidth: CGFloat {
        (width - 2 * Self.inset - CGFloat(columnCount - 1) * Self.spacing) / CGFloat(columnCount)
    }

    var body: some View {
        let _ = daysSeen
        let sections = browser.sections(in: library, order: order, now: library.now())
        let ids = sections.flatMap { $0.items.map(\.id) }
        let title = browser.isSearching ? String(localized: "Search") : library.name(of: browser.item)
        keyboardCollection(sections, ids: ids)
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
                    EmptyState.search(browser.searchText)
                        .accessibilityIdentifier("GalleryEmptySearch")
                } else { EmptyState(browser.item == .files ? "No Files" : "No Items") }
            }
        }
        .navigationTitle(title)
        .navigationSubtitle(browser.isSearching ? Text("^[\(ids.count) result](inflect: true)") : Text("^[\(ids.count) item](inflect: true)"))
        .toolbar(removing: browser.isSearchExpanded ? .title : nil)
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) { daysSeen += 1 }
        }
        .dragContainer(for: NoteReference.self) { ids in
            ids.compactMap { library.body(of: $0) }.map { NoteReference(id: $0.id, markdown: $0.text) }
        }
        .dragContainerSelection(Array(browser.selection))
    }

    private func collection(_ sections: [NoteSection], ids: [ItemID]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(sections) { section in
                        sectionGrid(section, ids: ids)
                    }
                }
                .padding(Self.inset)
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

    private func sectionGrid(_ section: NoteSection, ids: [ItemID]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let group = section.group {
                Text(group.title())
                    .interfaceFont(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: columnCount), spacing: Self.spacing + 4) {
                ForEach(section.items) { item in
                    card(item, ids: ids).id(item.id)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(section.group?.title() ?? String(localized: "Items"))
        }
    }

    private func keyboardCollection(_ sections: [NoteSection], ids: [ItemID]) -> some View {
        collection(sections, ids: ids)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: .down) { key in
            let current = cursor ?? ids.first(where: browser.selection.contains)
            let destination: ItemID?
            if key.key == .upArrow || key.key == .downArrow {
                destination = GallerySelection.movingVertically(from: current, sections: sections.map { $0.items.map(\.id) }, columns: columnCount, down: key.key == .downArrow)
            } else {
                destination = GallerySelection.moving(from: current, among: ids, by: key.key == .leftArrow ? -1 : 1)
            }
            guard let next = destination else { return .ignored }
            select(next, ids: ids, extending: key.modifiers.contains(.shift), toggling: false)
            return .handled
        }
        .onKeyPress(.return) {
            guard browser.selection.count == 1 else { return .ignored }
            browser.openCollectionSelection()
            return .handled
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

    private func card(_ item: Item, ids: [ItemID]) -> some View {
        Button {
            // SwiftUI Button actions do not expose the click's modifiers; AppKit supplies just that event.
            let modifiers = NSApp.currentEvent?.modifierFlags ?? []
            select(item.id, ids: ids, extending: modifiers.contains(.shift), toggling: modifiers.contains(.command))
            pane.wrappedValue = .list
        } label: {
            GalleryCard(
                item: item, selected: browser.selection.contains(item.id),
                date: NoteDate.listLabel(for: order.sort.date(of: item), now: library.now()), width: thumbnailWidth)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .contentShape([.interaction, .accessibility], .rect(cornerRadius: 10))
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            browser.selection = [item.id]
            browser.openCollectionSelection()
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue(browser.selection.contains(item.id) ? Text("Selected") : Text(""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(browser.selection.contains(item.id) ? .isSelected : [])
        .accessibilityIdentifier("GalleryItem-\(item.id.rawValue)")
        .accessibilityAction {
            select(item.id, ids: ids, extending: false, toggling: false)
            pane.wrappedValue = .list
        }
        .accessibilityAction(named: Text("Open")) {
            browser.selection = [item.id]
            browser.openCollectionSelection()
        }
        .contextMenu {
            let selected = browser.selection.contains(item.id) ? browser.selection : [item.id]
            Button("Open") { browser.selection = [item.id]; browser.openCollectionSelection() }
            Button("Open in New Window", systemImage: "macwindow") {
                for id in library.idsForWindows(selected) { openWindow(value: id) }
            }
            Divider()
            NoteActions(ids: selected, undoManager: undoManager)
        }
        .draggable(containerItemID: item.id)
    }

    private func select(_ id: ItemID, ids: [ItemID], extending: Bool, toggling: Bool) {
        if anchor == nil { anchor = ids.first(where: browser.selection.contains) }
        browser.selection = GallerySelection.selecting(id, among: ids, current: browser.selection, anchor: anchor, extending: extending, toggling: toggling)
        if !extending { anchor = id }
        cursor = id
    }

    private func deleteSelection() {
        let ids = browser.selection
        EditorController.flushAll(leaving: false) { [library, undoManager] kept in
            guard kept else { return }
            Browser.delete(ids, in: library, undoManager: undoManager)
        }
    }
}
