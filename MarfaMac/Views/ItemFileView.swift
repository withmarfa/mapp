import SwiftUI
import UniformTypeIdentifiers

/// Where a file item's file is, however the library gets it.
enum ItemFileResolution: Equatable {
    case ready(URL)
    /// The library has no file for the item.
    case unavailable
    /// The library has one but could not get it. `reason` is in the person's words where the library gave them, and
    /// nil where the person is only told to check the connection.
    case failed(reason: String?)

    /// The file, fetched from the library.
    @MainActor static func fetch(_ id: ItemID, in library: any ItemLibrary) async -> Self {
        do {
            return try await library.fileURL(of: id).map { .ready($0) } ?? .unavailable
        } catch let failure as SourceFailure {
            return .failed(reason: failure.message)
        } catch {
            return .failed(reason: nil)
        }
    }
}

/// Which item's file is shown. Each load names its item, and only the latest load is shown, so a slow answer
/// for one item, as from a Try Again before the window moved on, never shows or shares under another.
@Observable final class ItemFileLoader {
    private(set) var shown: (id: ItemID, resolution: ItemFileResolution)?
    @ObservationIgnored private var latest = 0

    func resolution(of id: ItemID) -> ItemFileResolution? {
        shown.flatMap { $0.id == id ? $0.resolution : nil }
    }

    /// The item's file as this load found it, or nil where a later load has taken its place.
    func load(_ id: ItemID, in library: any ItemLibrary) async -> ItemFileResolution? {
        latest += 1
        let load = latest
        shown = nil
        let fetched = await ItemFileResolution.fetch(id, in: library)
        guard load == latest, !Task.isCancelled else { return nil }
        shown = (id, fetched)
        return fetched
    }
}

/// A file item's file, shown once it is fetched, under the page's notice (`PageNotice`) where it has one: a deleted item,
/// a held write, and a file the library does not have. A picture, a PDF, audio and video keep their own scroller and take
/// the page's head, with the notice above it, as the first inset of it (`FileHeadSpace`), so the head scrolls away with
/// the file. Audio and video also have the playback bar at the foot, which says so while the file is on its way or could
/// not be had. Any other file's viewer has no head, and the notice stays above it.
struct ItemFileView: View {
    @CurrentLibrary private var library
    @StoredPageStyle private var style
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.settingsLauncher) private var settingsLauncher
    @AppStorage(InterfaceKey.showsPageToolbarBackground) private var showsToolbarBackground = true
    @State private var width: CGFloat = 0
    let id: ItemID
    /// The window the file's size and page are offered to once it is ready (`FileItemContent`).
    var details: DetailsPresentation?
    /// Shows the item a link in the head names.
    var open: (ItemID) -> Void = { _ in }
    /// Whether the page backs the toolbar with glass while the file is under it.
    var backsToolbar = true
    /// Told where the file is once it is, and nil when it is not, so a window can share it.
    var onResolved: (URL?) -> Void = { _ in }

    @State private var loader = ItemFileLoader()
    @State private var headerScroll = HeaderScroll()
    @State private var blockHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0

    private var item: Item? { library.item(id) }

    private var notices: [PageNotice] {
        guard let item else { return [] }
        if case .unavailable? = loader.resolution(of: id) { return PageNotice.all(for: item, fileIsMissing: true) }
        return PageNotice.all(for: item)
    }

    /// What the file is shown as, from the file once it is here and from the library's name for it until then.
    private var shownType: UTType? {
        guard let item else { return nil }
        let url: URL
        if case .ready(let ready)? = loader.resolution(of: id) { url = ready } else { url = URL(filePath: "/" + (item.name ?? "")) }
        return FileItemContent.type(of: url, contentType: item.fileType)
    }

    /// Whether the file is drawn with the head as its first inset: a picture, a PDF, audio or video.
    private var hasHead: Bool {
        guard let type = shownType else { return false }
        return FileViewKind.of(type) != nil || FileMedia.handles(type)
    }

    private var isMedia: Bool { shownType.map(FileMedia.handles) == true }

    private static let headerBlock = "fileHeaderBlock"

    var body: some View {
        // The task sits on one container. On the switch itself (`Group` hands a modifier to each branch) it would
        // start again with every branch, and a load changes the branch: the file would be fetched over and over.
        ZStack {
            if hasHead {
                GeometryReader { geometry in
                    let inset = style.horizontalInset(for: geometry.size.width)
                    ZStack(alignment: .top) {
                        content(space: FileHeadSpace(toolbar: geometry.safeAreaInsets.top, head: blockHeight, scrolled: scrolled))
                            .ignoresSafeArea(.container, edges: .top)
                        if let item {
                            ScrollingHeader(scroll: headerScroll) { headBlock(item, inset: inset) }
                        }
                        ScrollingToolbarBand(
                            scroll: headerScroll, toolbarHeight: geometry.safeAreaInsets.top, isEnabled: backsToolbar && showsToolbarBackground)
                    }
                }
            } else {
                content(space: nil)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if !notices.isEmpty {
                            PageNoticeView(notices: notices, run: run)
                                .padding(.horizontal, style.horizontalInset(for: width))
                                .padding(.vertical, 12)
                        }
                    }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .task(id: id) { await load() }
        .onChange(of: id) { old, _ in
            details?.headerScrolled(nil, for: old)
            headerScroll.reset()
        }
        .onChange(of: headerHeight) { feedAway() }
        .onChange(of: item?.displayTitle) { feedAway() }
        .onChange(of: details?.isFocused(on: id)) { _, focused in
            guard focused == true else { return }
            headerHeight = 0
            feedAway()
        }
        .onDisappear { details?.headerScrolled(nil, for: id) }
    }

    /// The notice and the head, one block whose height is the viewer's first inset.
    private func headBlock(_ item: Item, inset: CGFloat) -> some View {
        let isFocused = details?.isFocused(on: id) == true
        return VStack(spacing: 0) {
            if !notices.isEmpty {
                PageNoticeView(notices: notices, run: run)
                    .padding(.horizontal, inset)
                    .padding(.top, 12)
                    .padding(.bottom, isFocused ? 12 : 0)
            }
            // Focus leaves only the file: its title is in the toolbar and its properties are hidden.
            if !isFocused, let details {
                FilePageHead(item: item, inset: inset, drafts: details, open: open)
                    .onGeometryChange(for: CGFloat.self) { [space = Self.headerBlock] in $0.frame(in: .named(space)).maxY } action: { headerHeight = $0 }
            }
        }
        .coordinateSpace(name: Self.headerBlock)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { blockHeight = $0 }
        // Above the block too, so a file pulled past its start shows the window's color there.
        .background { Color(nsColor: .windowBackgroundColor).padding(.top, -1_000) }
    }

    @ViewBuilder private func content(space: FileHeadSpace?) -> some View {
        switch loader.resolution(of: id) {
        case nil:
            if isMedia {
                Color.clear.overlay { PlaybackFoot { PlaybackBar(mode: .gettingFile) } }
            } else {
                ProgressView("Getting File…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, space?.top ?? 0)
            }
        case .ready(let url):
            FileItemContent(url: url, title: item?.name ?? url.lastPathComponent, contentType: item?.fileType, item: id, details: details, head: space)
        // The page's notice says so.
        case .unavailable:
            Color.clear
        case .failed(let reason) where isMedia:
            // The bar says it and offers Try Again; the page keeps the reason the library gave.
            Text(reason ?? String(localized: "The app couldn’t get the file from the server. Check your connection, then try again."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, space?.top ?? 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay { PlaybackFoot { PlaybackBar(mode: .failed(retry: { Task { await load() } })) } }
        case .failed(let reason):
            ContentUnavailableView {
                Label("Can’t Get This File", systemImage: "exclamationmark.icloud")
            } description: {
                if let reason {
                    Text(reason)
                } else {
                    Text("The app couldn’t get the file from the server. Check your connection, then try again.")
                }
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
            .padding(.top, space?.top ?? 0)
        }
    }

    private func run(_ notice: PageNotice) {
        notice.run(in: library, undoManager: undoManager, openWindow: openWindow, openSettings: { [settingsLauncher] in settingsLauncher?.show($0) })
    }

    private func scrolled(_ offset: CGFloat) {
        headerScroll.scrolled(to: offset, isShowingPage: true)
        feedAway()
    }

    /// Tells the window once the head has gone under the toolbar, so the toolbar names the item.
    private func feedAway() {
        guard let item, let details else { return }
        let head = ScrolledHead(item: id, title: item.displayTitle, typeIcon: library.catalogue.icon(for: item.type))
        details.headerScrolled(hasHead && headerScroll.isAway(headerHeight: headerHeight) ? head : nil, for: id)
    }

    private func load() async {
        onResolved(nil)
        if case .ready(let url) = await loader.load(id, in: library) { onResolved(url) }
    }
}

/// The page of an item that is not shown as text (`ItemLibrary.pageLayout(of:)`): an HTML document in the sealed web
/// page, under the item's title, or any other file in its preview.
struct FileItemPage: View {
    @CurrentLibrary private var library
    let item: Item
    let drafts: DetailsPresentation
    /// Shows the item a link in the page names.
    let open: (ItemID) -> Void
    var onResolved: (URL?) -> Void = { _ in }
    /// Whether a web page or a file backs the toolbar with a band while it is scrolled under it (`WebPageItemPage`).
    var backsToolbar = true

    var body: some View {
        // The corner's Open takes the file from the window's presentation, so every window tells it.
        let resolved: (URL?) -> Void = { [id = item.id, drafts] url in
            drafts.fileResolved(url, for: id)
            onResolved(url)
        }
        if case .webPage(let document, let runsScripts) = library.pageLayout(of: item) {
            WebPageItemPage(
                item: item, document: document, runsScripts: runsScripts, drafts: drafts, open: open, onResolved: resolved,
                backsToolbar: backsToolbar)
        } else {
            ItemFileView(id: item.id, details: drafts, open: open, backsToolbar: backsToolbar, onResolved: resolved)
        }
    }
}
