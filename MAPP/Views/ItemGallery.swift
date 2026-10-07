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
    @State private var anchor: ItemID?
    @State private var cursor: ItemID?
    @State private var daysSeen = 0

    private var columnCount: Int {
        max(1, Int((width - 48 + 20) / (220 * InterfaceStyle.scale(for: textSize) + 20)))
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
                    ContentUnavailableView.search(text: browser.searchText)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("GalleryEmptySearch")
                } else { ContentUnavailableView(browser.item == .files ? "No Files" : "No Items", systemImage: browser.item == .files ? "doc" : "note.text") }
            }
        }
        .navigationTitle(title)
        .navigationSubtitle(browser.isSearching ? Text("^[\(ids.count) result](inflect: true)") : Text("^[\(ids.count) item](inflect: true)"))
        .toolbar {
            ColumnSearch(isExpanded: $browser.isSearchExpanded, text: $browser.searchText, prompt: String(localized: "Search"), columnWidth: min(width, 400), focusRequests: browser.searchFocusRequests, onDown: { browser.focusRequest = .list }) {
                Menu("Sort", systemImage: "arrow.up.arrow.down") { OrderOptions().pickerStyle(.inline) }
                    .menuIndicator(.hidden)
                    .help("Sort")
            }
        }
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
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(sections) { section in
                        sectionGrid(section, ids: ids)
                    }
                }
                .padding(24)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Items")
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
        .background(.windowBackground)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { if $0.isFinite, $0 > 0 { width = $0 } }
    }

    private func sectionGrid(_ section: NoteSection, ids: [ItemID]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let group = section.group {
                Text(group.title())
                    .interfaceFont(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: columnCount), spacing: 20) {
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
            browser.openGallerySelection()
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
            GalleryCard(item: item, selected: browser.selection.contains(item.id), date: NoteDate.listLabel(for: order.sort.date(of: item), now: library.now()), folder: browser.showsFolders ? library.folder(of: item)?.name ?? String(localized: "Inbox") : nil)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .contentShape([.interaction, .accessibility], .rect(cornerRadius: 16))
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            browser.selection = [item.id]
            browser.openGallerySelection()
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
            browser.openGallerySelection()
        }
        .contextMenu {
            let selected = browser.selection.contains(item.id) ? browser.selection : [item.id]
            Button("Open") { browser.selection = [item.id]; browser.openGallerySelection() }
            Button("Open in New Window", systemImage: "macwindow") {
                for id in library.idsForWindows(selected) { openWindow(value: id) }
            }
            if selected.count == 1, library.canRenameFile(of: item) {
                Button("Rename…", systemImage: "pencil") { browser.renamingNote = item.id }
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
        EditorController.flushAll(leaving: false) { [library, undoManager] in
            Browser.delete(ids, in: library, undoManager: undoManager)
        }
    }
}

private struct GalleryCard: View {
    @CurrentLibrary private var library
    let item: Item
    let selected: Bool
    let date: String
    let folder: String?
    @State private var image: CGImage?

    var body: some View {
        let body = library.body(of: item.id)
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    GeometryReader { geometry in
                        Image(decorative: image, scale: 1).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    }
                } else {
                    Rectangle().fill(.background)
                    VStack(alignment: .leading, spacing: 12) {
                        if item.isFile {
                            Image(systemName: "doc").interfaceFont(.largeTitle).foregroundStyle(.secondary)
                        } else {
                            Text(item.preview).interfaceFont(.body).lineLimit(6).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(18)
                    .padding(.bottom, 72)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).interfaceFont(.headline).lineLimit(2)
                    HStack {
                        if item.isFavorite { Image(systemName: "star.fill") }
                        if let folder { Text(folder).lineLimit(1) }
                        Spacer(minLength: 4)
                        Text(date).lineLimit(1)
                    }
                    .interfaceFont(.caption)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(image == nil ? Color.primary : .white)
                .background {
                    if image != nil { LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom).padding(.top, -32) }
                    else { Rectangle().fill(.background) }
                }
            }
            .clipShape(.rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 3 : 1) }
            .task(id: GalleryPreviewRequest(id: item.id, version: item.version, body: body?.text)) {
                image = nil
                let preview = await GalleryPreview.image(for: item, body: body?.text, in: library)
                if !Task.isCancelled { image = preview }
            }
    }
}
