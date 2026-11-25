import AppKit
import SwiftUI

/// Mounts one split view at a time: the workspace identity changes to switch. The column count of a mounted split view is never changed. Browser, editor, undo, columns and sidebar scroll live above that boundary so they survive a switch.
struct MainView: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @State private var browser = Browser()
    @State private var editorSlot = EditorSlot()
    @State private var details = DetailsPresentation()
    @SceneStorage("detailsPresented") private var storedDetailsPresented = false
    @StoredOrder private var order
    @SceneStorage("window") private var storedBrowser: Data?
    /// What earlier copies kept for the window, which they still read: read when the window has nothing newer, never written.
    @SceneStorage("browser") private var earlierBrowser: Data?
    @FocusState private var pane: Browser.Pane?
    @AppStorage(InterfaceKey.showsSidebarHistory) private var showsSidebarHistory = true
    /// Kept with the window for the next launch, as the selection and the details are.
    @SceneStorage("sidebarHidden") private var isSidebarHidden = false
    @State private var snapshotSaver = DelayedAction()
    @State private var measuredWidths = ColumnWidthTracker()
    @Environment(\.appearsActive) private var appearsActive
    /// Absent in previews and tests that build the window alone.
    @Environment(ItemLinkOpener.self) private var itemLinks: ItemLinkOpener?
    /// Whether the window has restored what it showed, before which an item link waits, so the restore does not
    /// replace the item the link opened.
    @State private var isRestored = false
    /// How far the list in front has scrolled, which the top row reads to bring the views up beside the title.
    @State private var listScroll = TopRowScroll()
    /// The window's width, which folds the panel and then the sidebar as the window narrows (`foldForWidth`).
    @State private var windowWidth: CGFloat = 0
    /// Whether the window folded the panel or the sidebar itself, and so opens it again when the room returns, also after
    /// a quit. Kept with the window, so a panel or sidebar folded by the width is never taken for one the person closed,
    /// which stays closed.
    @SceneStorage("panelFolded") private var foldedPanel = false
    @SceneStorage("sidebarFolded") private var foldedSidebar = false
    private let restoresWindow: Bool

    init(browser: Browser = Browser(), details: DetailsPresentation = DetailsPresentation(), restoresWindow: Bool = true) {
        _browser = State(initialValue: browser)
        _details = State(initialValue: details)
        self.restoresWindow = restoresWindow
    }

    /// The window's editor, holding the window's title drafts.
    private var editor: EditorController {
        editorSlot.editor { Self.makeEditor(library: library, details: details) }
    }

    /// An editor that holds `details` as its window's title drafts, so a quit saves a title typed and not left.
    static func makeEditor(library: any ItemLibrary, details: DetailsPresentation) -> EditorController {
        let editor = EditorController(library: library)
        editor.titleDrafts = details
        return editor
    }

    var body: some View { lifecycleWindow }

    /// The gallery and the table have no list column, so they mount the two-column split view, as does the list while
    /// an item is open as a full page.
    private var usesCollectionLayout: Bool { browser.usesCollection || browser.isCollectionItemPresented }

    private var workspacePresentation: WorkspacePresentation {
        if details.history != nil { return .history }
        if browser.showsPlaceIndex { return .index }
        return usesCollectionLayout ? .collection : .list
    }

    private var shownPresentation: WorkspacePresentation { workspacePresentation }
    private var shownViewMode: ItemViewMode { browser.viewMode }

    private var activeWindow: some View {
        // Release the outgoing toolbar providers before changing the column count.
        // Browser, editor, drafts, and column preferences remain above this presentation identity.
        dialogsWindow.id(shownPresentation)
        .onChange(of: workspacePresentation) {
            editor.flush()
            // Version History takes the whole window, which the modal would otherwise stay over.
            if workspacePresentation == .history { browser.closeModal(returningFocus: false) }
        }
        // What the modal held is saved as it opens and as it closes, and the page goes back to the layout.
        .onChange(of: browser.isModalPresented) { _, isOpen in
            if !isOpen { editor.releaseFocus() }
            editor.flush()
        }
        .onChange(of: appearsActive, initial: true) {
            ColumnWidthRegistry.shared.windowBecame(active: appearsActive, tracker: measuredWidths)
            if appearsActive { FrontBrowser.shared.last = browser }
        }
        .onChange(of: itemLinks?.request) { takeItemLink() }
        // Customizing happens in the sidebar, so a command that starts it brings the sidebar back.
        .onChange(of: browser.customizesSidebar) {
            if browser.customizesSidebar { isSidebarVisible = true }
        }
        .onChange(of: browser.showsCollection) {
            if browser.showsCollection { editor.releaseFocus(); editor.flush() }
        }
        // Another place, or the index of one, is somewhere else to go: Version History is of the item it was opened for.
        .onChange(of: browser.showing?.memoryKey) { details.leaveHistory() }
        .onChange(of: browser.showsPlaceIndex) { details.leaveHistory() }
    }

    private var isSidebarVisible: Bool {
        get { !isSidebarHidden }
        nonmutating set { isSidebarHidden = !newValue }
    }

    // Both native split shapes read the same sidebar preference before their first layout.
    private var listColumnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding { isSidebarVisible ? .all : .doubleColumn } set: { isSidebarVisible = $0 == .all }
    }

    private var galleryColumnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding { isSidebarVisible ? .all : .detailOnly } set: { isSidebarVisible = $0 == .all }
    }

    private var splitView: some View {
        // The gallery and the table replace this entire split view rather than changing the columns inside it.
        NavigationSplitView(columnVisibility: listColumnVisibility) {
            sidebarColumn
        } content: {
            ItemList(browser: browser, order: order, pane: $pane).equatable()
                .filterChips(browser)
                .topRowOverList(browser: browser, scroll: listScroll, opensPlaces: !isSidebarVisible, isSmall: isSmallWindow, signal: topRowSignal)
                // The split view reads the ideal only as it is built, so it comes from the tracker as it stands then.
                .navigationSplitViewColumnWidth(
                    min: ColumnWidth.list.range.lowerBound, ideal: measuredWidths.width(of: .list),
                    max: ColumnWidth.list.range.upperBound)
        } detail: {
            // The modal holds the window's one editor while it is open, so the page beside the list steps aside.
            Group {
                if browser.isModalPresented { Color.clear } else { itemPage.topRowOverPage(tools: pageTools, signal: topRowSignal) }
            }
                .toastOverlay()
                .modifier(itemInspector)
                .toolbar { windowToolbar(hasListColumn: true) }
        }
    }

    private func windowToolbar(hasListColumn: Bool = false) -> WindowToolbar {
        WindowToolbar(
            browser: browser, items: browser.selectedHeaderItems(in: library), editor: editor, details: details,
            hasListColumn: hasListColumn, hasHistory: showsSidebarHistory,
            leadsWithHistory: !isSidebarVisible && showsSidebarHistory && !hasListColumn)
    }

    /// What the top row of a page reads, which the toolbar's own items read too.
    private var pageTools: ItemToolbarActions {
        ItemToolbarActions(library: library, browser: browser, items: browser.selectedHeaderItems(in: library), editor: editor, details: details)
    }

    /// What changes the toolbar's items beside a row, so the row measures its room again.
    private var topRowSignal: AnyHashable {
        AnyHashable(TopRowSignal(
            isSearching: browser.isSearchExpanded, isPanelOpen: details.isPresented, isSidebarVisible: isSidebarVisible,
            isPage: browser.isCollectionItemPresented, hasSelection: !browser.selection.isEmpty, layout: browser.viewMode))
    }

    /// Only the three-column split has a list column to measure.
    private var hasListColumn: Bool { shownPresentation == .list }

    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            Sidebar(browser: browser, order: order)
                // In SwiftUI's focus system, so the sidebar's own keys (Return, Delete) reach it.
                .focused($pane, equals: .sidebar)
        }
        .onSplitViewDividerDrag(placing: {
            hasListColumn
                ? [measuredWidths.width(of: .sidebar), measuredWidths.width(of: .list)]
                : [measuredWidths.width(of: .sidebar)]
        }) { widths in
            if let sidebar = widths.first { measuredWidths.record(sidebar, for: .sidebar) }
            if hasListColumn, widths.count > 1 { measuredWidths.record(widths[1], for: .list) }
        }
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            SidebarToolbar(browser: browser, isSidebarVisible: Binding { isSidebarVisible } set: { isSidebarVisible = $0 })
        }
        // Last: under a toolbar the split view reads no limits, and the sidebar drags to any width.
        .navigationSplitViewColumnWidth(
            min: ColumnWidth.sidebar.range.lowerBound, ideal: measuredWidths.width(of: .sidebar), max: ColumnWidth.sidebar.range.upperBound)
    }

    private var itemPage: some View {
        ItemDetail(browser: browser, editor: editor, details: details)
    }

    /// An item's page filling the content, where the list that held the keyboard has gone. The page takes the keyboard
    /// itself, so Escape still reaches `escapesFromPage` before anything is clicked.
    private var fullPage: some View {
        itemPage
            .focusable()
            .focusEffectDisabled()
            .focused($pane, equals: .page)
            .onAppear { pane = .page }
    }

    private var workspace: some View {
        Group {
            if let history = details.history, shownPresentation == .history {
                VersionHistoryWorkspace(mode: history, details: details)
                    .toastOverlay()
            } else if shownPresentation == .index {
                NavigationSplitView(columnVisibility: galleryColumnVisibility) {
                    sidebarColumn
                } detail: {
                    PlaceIndex(browser: browser, details: details, order: order, pane: $pane)
                        .topRowOverList(browser: browser, scroll: listScroll, opensPlaces: !isSidebarVisible, isSmall: isSmallWindow, signal: topRowSignal)
                        .toastOverlay()
                        .toolbar { windowToolbar() }
                }
            } else if shownPresentation == .collection {
                NavigationSplitView(columnVisibility: galleryColumnVisibility) {
                    sidebarColumn
                } detail: {
                    Group {
                        if browser.showsCollection {
                            Group {
                                switch browser.viewMode {
                                case .table:
                                    ItemTable(browser: browser, order: order, pane: $pane)
                                case .board:
                                    ItemBoard(browser: browser, pane: $pane)
                                case .timeline:
                                    ItemTimeline(browser: browser, pane: $pane)
                                case .calendar:
                                    ItemCalendar(browser: browser, pane: $pane)
                                case .list, .gallery:
                                    ItemGallery(browser: browser, order: order, pane: $pane)
                                }
                            }
                            .filterChips(browser)
                            .viewCorner(browser)
                            .topRowOverList(browser: browser, scroll: listScroll, opensPlaces: !isSidebarVisible, isSmall: isSmallWindow, signal: topRowSignal)
                        } else {
                            fullPage.topRowOverPage(tools: pageTools, signal: topRowSignal)
                        }
                    }
                    .toastOverlay()
                    .modifier(itemInspector)
                    .toolbar { windowToolbar() }
                }
                // Each view has its own split view: swapped inside one, the next squeezes the right sidebar to its
                // minimum. Only the split is remade, as the dialogs above it watch the view for a saved view's layout.
                .id(shownViewMode)
            } else {
                splitView
            }
        }
    }

    private var itemInspector: ItemInspectorColumn {
        ItemInspectorColumn(browser: browser, details: details, editor: editor)
    }

    /// Under this width the panel folds, and under the next the sidebar does; under the last the views are one pill beside
    /// the title (the window's smallest is 760 wide).
    private static let panelFoldsBelow: CGFloat = 1000
    private static let sidebarFoldsBelow: CGFloat = 900
    private static let viewsFoldBelow: CGFloat = 800

    private var isSmallWindow: Bool { windowWidth > 0 && windowWidth < Self.viewsFoldBelow }

    /// Folds the panel and then the sidebar as the window narrows past their widths, and opens them again as it widens, but
    /// only what it folded itself. It acts when the width crosses a limit, so a person who opens one in a narrow window
    /// keeps it open. The first width is where the window starts, not a crossing: it folds nothing, and only opens again
    /// what a quit left folded.
    private func foldForWidth(from old: CGFloat, to new: CGFloat) {
        func crossed(_ limit: CGFloat) -> Bool? {
            if new < limit, old >= limit { return true }
            if new >= limit, old < limit { return false }
            return nil
        }
        if let folds = crossed(Self.panelFoldsBelow) {
            // A panel opened for the moment, as by Customize Layout, is not the person's, so it is not opened again.
            if folds, details.isPresented { foldedPanel = details.isPresentedByPerson; details.isPresented = false }
            else if !folds, foldedPanel { foldedPanel = false; details.isPresented = true }
        }
        if let folds = crossed(Self.sidebarFoldsBelow) {
            if folds, isSidebarVisible { foldedSidebar = true; isSidebarVisible = false }
            else if !folds, foldedSidebar { foldedSidebar = false; isSidebarVisible = true }
        }
    }

    private var presentedWindow: some View {
        workspace
        // The window keeps a title for Mission Control and VoiceOver; the top row draws it.
        .navigationTitle(library.name(of: browser.shown))
        .hidesWindowTitle()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { new in
            let old = windowWidth
            windowWidth = new
            foldForWidth(from: old, to: new)
        }
        // The window's toolbar is part of what a modal covers: dimmed and silent, as behind a sheet.
        .disabled(browser.isModalPresented)
        .escapesFromPage(details)
        .overlay {
            ZStack {
                if browser.isModalPresented {
                    ItemModal(browser: browser, editor: editor, details: details)
                        // Gone at once on close: a fading card would still host the editor the page beside the list takes.
                        .transition(.asymmetric(insertion: .opacity, removal: .identity))
                }
            }
            .animation(.easeOut(duration: 0.15), value: browser.isModalPresented)
        }
        .focusedSceneValue(\.detailsPresentation, details)
        .modifier(CommandValuePanels(details: details))
        .modifier(FieldEditSheets(details: details))
        .sheet(item: Binding { details.typeValues } set: { details.typeValues = $0 }) { TypeValuesSheet(request: $0) }
        .onChange(of: details.isPresentedByPerson) {
            // What the window folded is not the person's choice: the panel the person opens is theirs again.
            if details.isPresentedByPerson { foldedPanel = false }
            if restoresWindow { storedDetailsPresented = details.isPresentedByPerson }
        }
        .onChange(of: isSidebarVisible) { if isSidebarVisible { foldedSidebar = false } }
        // Closing the sidebar by hand finishes Customize Layout, which has nowhere else to show.
        .onChange(of: details.isPresented) { if !details.isPresented { details.endLayout() } }
        // Leaving the page finishes it too, as there is nothing left to arrange.
        .onChange(of: browser.showsPage, initial: true) {
            details.showsPage = browser.showsPage
            if !browser.showsPage { details.endLayout() }
        }
        .overlay(alignment: .top) {
            if let palette = browser.palette {
                FloatingPanel {
                    browser.palette = nil
                    browser.focusRequest = .list
                } content: {
                    CommandPalette(browser: browser, editor: editor, mode: palette)
                        // Each palette starts afresh, as ⌘K's Search Items moves from one to the other.
                        .id(palette)
                }
            } else if browser.quickAdd.isPresented, browser.quickAdd.draft != nil {
                FloatingPanel {
                    browser.putAwayQuickAdd()
                    if browser.focusRequest == nil { browser.focusRequest = .list }
                } content: {
                    QuickAddPanel(browser: browser, quickAdd: browser.quickAdd, editor: editor)
                }
            }
        }
        .focusedSceneValue(\.browser, browser)
        .focusedSceneValue(\.editor, browser.showsPage ? editor : nil)
        .focusedSceneValue(\.focusedItems, FocusedItems(ids: browser.selection, undoManager: undoManager))
        // Last, so the toolbars, the context menus and the palette above the workspace all read it.
        .environment(details)
    }

    private var lifecycleWindow: some View {
        activeWindow
        .watchesPlace(browser, order: order)
        // The page grants its own requests, since it may not exist until the request's selection shows.
        .onChange(of: browser.focusRequest, grantFocusRequest)
        // A draft the inspector held back is given back when the selection moves off its item, shown or not. Folding
        // a section or hiding the inspector keep it, and the item still shown keeps its own.
        .onChange(of: browser.selection) {
            // Selecting another item, or following a link, leaves the history of the one it was opened for.
            if let history = details.history, browser.selection != [history.item] { details.leaveHistory() }
            details.handOffProperties(except: browser.selection.count == 1 ? browser.selection.first : nil, in: library, undoManager: undoManager)
        }
        .onChange(of: browser.snapshotParts) {
            if restoresWindow {
                browser.saveSnapshot { storedBrowser = $0 }
                if browser.laterPlace == nil { StartWith.remember(browser.shown) }
            }
        }
        // The window has gone, by closing or changing library, once its titles were saved or the person chose to
        // go; its drafts take no part in what other windows do. The library is the one this view showed, so a
        // window whose libraries now read another has changed library rather than closed.
        .onDisappear { [library, libraries] in
            editorSlot.made?.flush()
            editorSlot.made?.windowWent()
            let changed = libraries.current.map { ObjectIdentifier($0) != ObjectIdentifier(library) } ?? true
            details.handOffProperties(in: library, undoManager: nil)
            browser.quickAdd.handOff(to: library.notices, because: changed ? .libraryChanged : .closed, in: library)
            browser.giveUpNewItem(because: .windowLeft)
            browser.viewPanel?.handOff(because: changed ? .libraryChanged : .closed)
        }
        .onAppear {
            if restoresWindow { details.isPresented = storedDetailsPresented }
            // The window's width may have arrived before what it restored, so what a quit left folded opens again now.
            if windowWidth > 0 { foldForWidth(from: 0, to: windowWidth) }
            let editor = editor
            if restoresWindow {
                // The position is saved once the person stops scrolling, not for every line of it.
                let stored = $storedBrowser
                browser.listMemory.scrolled = { [snapshotSaver, browser] in
                    snapshotSaver.schedule { browser.saveSnapshot { stored.wrappedValue = $0 } }
                }
            }
            editor.onChange = { [library] id, markdown, read in library.updateBody(of: id, to: markdown, readAt: read) }
            editor.onEscape = { [browser, details, library] in
                if details.isEditingView { browser.escapeViewPanel(in: library) }
                else if details.isCustomizingLayout { details.endLayout() }
                else if details.escapeFromPage() { return }
                else if browser.isModalPresented { browser.closeModal() }
                else { browser.focusRequest = .list }
            }
            browser.windowOpener = { [library, openWindow] ids in
                ItemWindows.open(library.idsForWindows(ids)) { openWindow(value: $0) }
            }
            editor.onOpenItem = { [browser, library, order] id in
                if let item = library.item(id) { browser.open(linked: item, in: library, order: order) }
            }
            editor.onFollowItemLink = { [browser, library, order] id in
                if let item = library.item(id) { browser.follow(link: item, in: library, order: order) }
            }
            editor.onShowRefusedTitle = { [browser, library, order] id in
                if let item = library.item(id) { browser.reveal(item, in: library, order: order) }
            }
        }
        // Another Mac's settings reached the defaults: a list reads its density again.
        .onReceive(NotificationCenter.default.publisher(for: PreferencesSync.appliedNotification)) { _ in browser.densityRevision += 1 }
        // A window restores what it showed once the library has been read, since before then nothing is there. A
        // window carried to another library starts afresh with it.
        .onChange(of: library.isLoaded, initial: true) {
            browser.adopt(library, undoManager: undoManager)
            guard library.isLoaded else { return }
            // After this update, not in it: chosen while the window's toolbars are first mounted, the page
            // can miss the selection and stay on No Item Selected.
            Task {
                if restoresWindow { browser.restore(from: storedBrowser ?? earlierBrowser, in: library, order: order, start: StartWith.stored().start()) }
                // A window opened for one of the Library's places shows it.
                if let place = PlaceWindows.take() { browser.show(place, in: library, order: order) }
                #if DEBUG
                if SampleLibrary.isRequested, SampleLibrary.withCollections {
                    browser.showing = .type(TypeID("core.task"))
                    browser.set(layout: .board)
                }
                if let place = SampleLibrary.launchPlace {
                    // A type with no item yet has no place to stay on, so a server's copy still filling is waited for.
                    let scope = PlaceDefaults.favoritesScope(in: UserDefaults.standard.data(forKey: PlaceDefaults.key))
                    for _ in 0..<60 where library.count(in: place, favoritesScope: scope) == 0 { try? await Task.sleep(for: .milliseconds(500)) }
                    browser.showing = place
                }
                if let layout = SampleLibrary.launchLayout { browser.set(layout: layout) }
                #endif
                isRestored = true
                takeItemLink()
            }
        }
        // A new item reaches a server's library when its source says so, which the window waits for to open it.
        .onChange(of: newItemIsSettled) {
            if newItemIsSettled { browser.finishNewItem(in: library) }
        }
        // The files quick add attached go at the end of the new item's text, once the page shows it.
        .onChange(of: browser.newEmbeds) {
            guard let attached = browser.newEmbeds else { return }
            browser.newEmbeds = nil
            editor.append(attached.embeds, to: attached.id)
        }
        #if DEBUG
        // A sample launch can open an item without a click, as `-MarfaMacSelectItem <id>`, once the library holds it.
        .onChange(of: launchSelection.map { library.item($0) != nil }, initial: true) {
            if let id = launchSelection, library.item(id) != nil { browser.selection = [id] }
        }
        #endif
    }

    private var dialogsWindow: some View {
        presentedWindow
        .libraryDialogs()
        .handlesFiles(in: browser, order: order)
        .deleteConfirmation(for: details)
        .archiveQuestion(for: details)
        .feedLimitQuestion(for: details)
        .savedViewDialogs(browser: browser, details: details)
    }

    private var newItemIsSettled: Bool { browser.isNewItemSettled(in: library) }

    /// Opens the item a `marfa://` link named in this window (`Browser.open(itemLink:)`), once it has restored what it
    /// showed. The opener checks the link against this window's library; this window only shows the item.
    private func takeItemLink() {
        guard isRestored, let itemLinks else { return }
        let library = library
        Task {
            guard let item = await itemLinks.take(for: browser, in: library), library === self.library else { return }
            // Version History takes the whole window, which would hide the item.
            details.leaveHistory()
            browser.open(itemLink: item, in: library, order: order)
        }
    }

    #if DEBUG
    private var launchSelection: ItemID? {
        let arguments = ProcessInfo.processInfo.arguments
        guard SampleLibrary.isRequested, let flag = arguments.firstIndex(of: "-MarfaMacSelectItem"),
              arguments.indices.contains(flag + 1) else { return nil }
        return ItemID(arguments[flag + 1])
    }
    #endif

    /// The list's search comes out as a field, which takes the keyboard.
    private func grantFocusRequest() {
        switch browser.focusRequest {
        case .search:
            browser.showSearchField()
        case .sidebar, .list:
            editor.releaseFocus()
            // Asked for as the place changes, the list that takes the keyboard is not yet in the window.
            let request = browser.focusRequest
            Task { pane = request }
        case .page, .title:
            // The modal's own page takes the request, and no full page is opened behind it.
            if browser.showsCollection, !browser.isModalPresented { browser.isCollectionItemPresented = true }
            return
        case nil: return
        }
        browser.focusRequest = nil
    }
}

private enum WorkspacePresentation: Hashable {
    case list, collection, index, history
}

/// What changes the toolbar's items beside the top row, which the row measures again when any of it changes.
private struct TopRowSignal: Hashable {
    let isSearching: Bool
    let isPanelOpen: Bool
    let isSidebarVisible: Bool
    let isPage: Bool
    let hasSelection: Bool
    let layout: ItemViewMode
}

/// Applied to a detail column, before its toolbar, never to the split view: an inspector on the split view makes every
/// resize of the window lay out every column again, which made live resizing several times slower, and one applied
/// after the column's toolbar raises an exception during layout when a new window opens.
private struct ItemInspectorColumn: ViewModifier {
    let browser: Browser
    let details: DetailsPresentation
    let editor: EditorController
    /// Read once, as the window remakes this column when its layout changes and the column's own width goes with it.
    /// Kept out of the state as it changes, so a drag is not fed back into the column it is resizing.
    @State private var width = UserDefaults.standard.object(forKey: InterfaceKey.inspectorWidth) as? Double ?? PanelWidth.standard

    /// Whether the person is dragging the sidebar's own edge, which is what chooses its width. Dragging another divider
    /// or the window's edge can squeeze the sidebar too, and that is not a choice to keep.
    private static func isDraggingEdge(ofSidebarWidth width: CGFloat) -> Bool {
        guard let event = NSApp.currentEvent, event.type == .leftMouseDragged, let window = event.window else { return false }
        return abs(window.frame.width - width - event.locationInWindow.x) < 8
    }

    func body(content: Content) -> some View {
        // While the modal is open its own sidebar shows the details, so this one is out and only one is mounted.
        content.inspector(isPresented: Binding { details.isPresented && !browser.isModalPresented } set: { details.isPresented = $0 }) {
            ItemInspectorHost(browser: browser, details: details, editor: editor)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                    guard details.isPresented, Self.isDraggingEdge(ofSidebarWidth: newWidth) else { return }
                    UserDefaults.standard.set(Double(newWidth), forKey: InterfaceKey.inspectorWidth)
                }
                .inspectorColumnWidth(min: PanelWidth.standard, ideal: width, max: PanelWidth.widest)
                .toolbar { InspectorToolbar(details: details, editor: editor, browser: browser) }
        }
    }
}
