import MarfaIcons
import SwiftUI

/// An item shown as an HTML document: its title and byline in the manner of the note page's header, then the HTML
/// filling the rest of the detail area, shown as it was written (`WebPageView`). The document is the item's own file, for
/// a Web Page or an HTML file, or the HTML file attached to it, for a document a connector keeps that way
/// (`ItemLibrary.pageLayout(of:)`). The body is read only, and the item's title and properties are not edited on the
/// page; the inspector shows them.
///
/// Its pictures are the app's to give (`SealedPictures`), for this item: while some wait for the person, a callout at the
/// top of the page says how many and loads them, as on a note's page.
struct WebPageItemPage: View {
    private enum Content: Equatable {
        case loading
        /// The document with its pictures pointed at the app, and the encoding to read it in.
        case ready(Data, String.Encoding)
        /// The library has no file for the item.
        case unavailable
        /// The library has one but could not get it.
        case failed
        /// The file is not an HTML page.
        case notHTML
    }

    private struct Load: Hashable {
        let id: ItemID
        let document: ItemID
        let version: ItemVersion?
    }

    @CurrentLibrary private var library
    @StoredPageStyle private var style
    @AppStorage(RemotePictureSetting.key) private var remotePictures = RemotePictureSetting.standard
    let item: Item
    /// The file that holds the HTML.
    let document: ItemID
    let runsScripts: Bool
    /// Told where the item's file is once it is, and nil when it is not, so the window can share it and open it in a
    /// browser. Never told of a document attached to the item.
    var onResolved: (URL?) -> Void = { _ in }

    @State private var loader = ItemFileLoader()
    @State private var content = Content.loading
    @State private var shownID: ItemID?
    @State private var pictures: SealedPictures?
    @AppStorage(InterfaceKey.textSize) private var interfaceTextSize = InterfaceStyle.defaultTextSize

    /// One step of the callout's spacing, as on the note page.
    private var calloutGap: CGFloat { CGFloat(interfaceTextSize) * 4 / 13 * 4 }

    var body: some View {
        GeometryReader { geometry in
            let inset = style.horizontalInset(for: geometry.size.width)
            VStack(spacing: 0) {
                WebPageHeader(item: item, inset: inset)
                // The header is inset like the other item pages' and the page draws to its own margin, so the line
                // sets the page apart as a document under its header.
                Divider()
                // At the top of the page, clearly further from the header than from the text it belongs to.
                if let pictures, pictures.waitingCount > 0 {
                    PicturesWaitingCallout(count: pictures.waitingCount) { pictures.loadWaiting() }
                        .padding(.horizontal, inset)
                        .padding(.top, calloutGap * 2)
                        .padding(.bottom, calloutGap * 0.75)
                }
                pageBody
            }
        }
        .accessibilityIdentifier("WebPageItemPage")
        .task(id: Load(id: item.id, document: document, version: library.item(document)?.version)) { await load() }
        .onChange(of: remotePictures) { pictures?.redraw() }
        .onChange(of: library.savedPictureStates(of: item.id)) { pictures?.redraw() }
    }

    @ViewBuilder private var pageBody: some View {
        switch content {
        case .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let html, let encoding):
            WebPageView(html: html, encoding: encoding, pictures: pictures, runsScripts: runsScripts)
                // Each item's pictures are answered by a page made for it.
                .id(pictures.map(ObjectIdentifier.init))
        case .unavailable:
            ContentUnavailableView {
                Label("File Unavailable", systemImage: "questionmark.folder")
            } description: {
                Text("The file for this page isn’t in Marfa.")
            }
        case .failed:
            ContentUnavailableView {
                Label("Can’t Get This File", systemImage: "exclamationmark.icloud")
            } description: {
                Text("MAPP couldn’t get the file from the server. Check your connection, then try again.")
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        case .notHTML:
            ContentUnavailableView {
                Label("Can’t Show This Page", systemImage: "doc.questionmark")
            } description: {
                Text("This file isn’t an HTML page.")
            }
        }
    }

    private func load() async {
        onResolved(nil)
        // A change to the same item's file is shown over the page it replaces, not a blank one.
        if shownID != item.id {
            content = .loading
            let id = item.id
            pictures = SealedPictures(
                item: id, pictures: .standard, inFeed: { [library] in library.item(id)?.tier == .feed },
                saved: { [library] address in await library.openSavedPicture(of: id, at: address) })
        }
        shownID = item.id
        guard let pictures, WebPageFile.isHTML(library.item(document)?.fileType) else {
            content = .notHTML
            return
        }
        switch await loader.load(document, in: library) {
        case nil:
            return
        case .unavailable:
            content = .unavailable
        case .failed:
            content = .failed
        case .ready(let url):
            // The file of an item that is itself a file is the item; a document attached to one is not, so the item
            // shares and opens as it would without it.
            if document == item.id { onResolved(url) }
            let (item, version) = (item.id, pictures.version)
            do {
                let rewritten = try await Task.detached(priority: .userInitiated) {
                    SealedPictureRewrite.rewrite(try Data(contentsOf: url), item: item, version: version)
                }.value
                guard !Task.isCancelled else { return }
                pictures.show(rewritten.addresses, version: version)
                content = .ready(rewritten.html, rewritten.encoding)
            } catch {
                guard !Task.isCancelled else { return }
                content = .failed
            }
        }
    }
}

/// At the top of the page while some of its pictures wait for the person, in the words and the look of the callout on a
/// note's page, which follows Mail's mailing-list banner: how many are not loaded, and a pill button that loads them.
/// Its measures are the note page's, in steps of 4/13 of the interface text size (4 points at 13).
struct PicturesWaitingCallout: View {
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize
    let count: Int
    let load: () -> Void

    var body: some View {
        let size = CGFloat(textSize)
        let step = size * 4 / 13
        HStack(spacing: step * 3) {
            Image(systemName: "photo")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Group {
                if count == 1 {
                    Text("1 picture from another website isn’t loaded.")
                } else {
                    Text("\(count) pictures from other websites aren’t loaded.")
                }
            }
            .fontWeight(.medium)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: load) {
                if count == 1 { Text("Load Picture") } else { Text("Load Pictures") }
            }
            .buttonStyle(PicturePillStyle(step: step))
        }
        .font(.system(size: size))
        .padding(.horizontal, step * 3)
        .padding(.vertical, step * 2.5)
        .background(.quinary, in: RoundedRectangle(cornerRadius: step * 3.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PicturesWaitingCallout")
    }
}

/// A tinted pill with no border, brighter under the pointer.
private struct PicturePillStyle: ButtonStyle {
    let step: CGFloat
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .foregroundStyle(.tint)
            .padding(.horizontal, step * 3)
            .padding(.vertical, step)
            .background(.tint.opacity(hovering || configuration.isPressed ? 0.26 : 0.16), in: Capsule())
            .onHover { hovering = $0 }
    }
}

/// The title and the line under it: what the item is, who it came from and when. The sizes follow the note page's
/// header, a bold title at nearly twice the text size and a quiet secondary line at the interface's text size.
private struct WebPageHeader: View {
    @CurrentLibrary private var library
    @AppStorage(InterfaceKey.textSize) private var interfaceTextSize = InterfaceStyle.defaultTextSize
    @StoredPageStyle private var style
    let item: Item
    let inset: CGFloat

    var body: some View {
        let byline = PageByline(item: item, now: library.now())
        let type = library.catalogue.itemTypes[item.type]
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: item.title)
                .font(.system(size: CGFloat(style.textSize) * 1.9, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("WebPageTitle")
            HStack(spacing: 4) {
                TypeIcon(name: library.catalogue.icon(for: item.type))
                if let type { Text(verbatim: ItemPageHeader.localized(type.label)) }
                ForEach(Array([byline.source, byline.date].compactMap { $0 }.filter { !$0.isEmpty }.enumerated()), id: \.offset) { _, part in
                    Circle().fill(.secondary).opacity(0.7).frame(width: 2, height: 2).accessibilityHidden(true)
                    Text(verbatim: part)
                }
            }
            .font(.system(size: CGFloat(interfaceTextSize)))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("WebPageByline")
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, inset)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}
