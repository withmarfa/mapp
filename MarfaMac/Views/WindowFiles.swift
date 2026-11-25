import AppKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Makes the window take files imported from a nearby device by the File menu's Import from iPhone, each becoming
    /// an item through `Browser.importFiles`; and shows Quick Look for the browser's request.
    func handlesFiles(in browser: Browser, order: ItemOrder) -> some View {
        modifier(WindowFiles(browser: browser, order: order))
    }

    /// Makes a list take files dropped from Finder, which join the place in view (`Browser.fileDropTarget`). While
    /// they are held over it, a gray ring runs round it and a pill says what the drop does. The sidebar takes none.
    func takesDroppedFiles(in browser: Browser, order: ItemOrder) -> some View {
        modifier(DroppedFiles(browser: browser, order: order))
    }

    /// Space shows the selected items in Quick Look, from a list that has the keyboard.
    func quickLooksOnSpace(_ browser: Browser) -> some View {
        modifier(QuickLookOnSpace(browser: browser))
    }

    /// Makes the view take files and items dropped on it as the collection `id`'s: items join it, and files are
    /// added to the library and join it. A nil `id` leaves the view as it is, so a row that is not a collection can
    /// carry it. The view draws its own gray ground and ring while a drop is over it, unless `isTargeted` is given,
    /// which says so to a row that draws them itself.
    @ViewBuilder
    func dropsInto(collection id: ItemID?, browser: Browser, order: ItemOrder, isTargeted: Binding<Bool>? = nil) -> some View {
        if let id {
            modifier(CollectionDrop(collection: id, browser: browser, order: order, reports: isTargeted))
        } else {
            self
        }
    }
}

private struct WindowFiles: ViewModifier {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    let browser: Browser
    let order: ItemOrder

    func body(content: Content) -> some View {
        content
            .importsItemProviders(FileIntake.deviceTypes) { providers in
                guard !providers.isEmpty else { return false }
                browser.importProviders(providers, in: library, order: order, undoManager: undoManager, toasts: details?.toasts)
                return true
            }
            .quickLookPreview(
                Binding {
                    browser.quickLook?.current
                } set: { url in
                    if url == nil { browser.dismissQuickLook() } else { browser.quickLook?.current = url }
                },
                in: browser.quickLook?.urls ?? []
            )
            .onReceive(NotificationCenter.default.publisher(for: .quickLookTaken)) { note in
                if (note.object as? Browser) !== browser { browser.dismissQuickLook() }
            }
    }
}

private struct DroppedFiles: ViewModifier {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    @Environment(\.interfaceTextSize) private var textSize
    let browser: Browser
    let order: ItemOrder
    /// How many files are held over the list, or nil while none is.
    @State private var held: Int?

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.fileURL], delegate: FileDropHandler(held: $held) { providers in
                browser.importProviders(providers, in: library, order: order, undoManager: undoManager, toasts: details?.toasts)
            })
            .overlay {
                if let held {
                    FileDropRing(text: browser.fileDropTarget(in: library).pill(count: held), scale: InterfaceStyle.scale(for: textSize))
                }
            }
    }
}

private struct FileDropHandler: DropDelegate {
    @Binding var held: Int?
    let take: ([NSItemProvider]) -> Void

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

    func dropEntered(info: DropInfo) {
        held = FileDropHandler.count(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }

    func dropExited(info: DropInfo) { held = nil }

    func performDrop(info: DropInfo) -> Bool {
        held = nil
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        take(providers)
        return true
    }

    /// How many files the drag holds, read from the drag's own pasteboard, which the system fills as the drag starts:
    /// a folder is not one, and a file named twice counts once. Falls back to the providers where it names none.
    private static func count(_ info: DropInfo) -> Int {
        let urls = NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return info.itemProviders(for: [.fileURL]).count }
        let files = Set(
            urls.map { $0.resolvingSymlinksInPath() }
                .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true })
        return files.count
    }
}

/// A quiet gray ring 3 points wide, 5 inside the list, and one glass label near its foot that says what a drop does
/// (`FileDropTarget`).
private struct FileDropRing: View {
    let text: String
    let scale: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 3)
                .padding(5)
            Text(text)
                .font(.system(size: 13 * scale))
                .lineLimit(1)
                .padding(.horizontal, 14 * scale)
                .frame(height: 36 * scale)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 16)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct QuickLookOnSpace: ViewModifier {
    @CurrentLibrary private var library
    let browser: Browser

    func body(content: Content) -> some View {
        content.onKeyPress(.space, phases: .down) { press in
            guard press.modifiers.isEmpty, !browser.selection.isEmpty else { return .ignored }
            Task { await browser.quickLookSelection(in: library) }
            return .handled
        }
    }
}

private struct CollectionDrop: ViewModifier {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    let collection: ItemID
    let browser: Browser
    let order: ItemOrder
    /// Where a row that draws the ground and ring itself is told that a drop is over it.
    let reports: Binding<Bool>?
    @State private var isOverItems = false
    @State private var isOverFiles = false

    private var isTargeted: Bool { isOverItems || isOverFiles }

    func body(content: Content) -> some View {
        content
            .dropDestination(for: ItemReference.self) { references, _ in
                browser.addDropped(
                    Set(references.map(\.id)), to: collection, in: library, undoManager: undoManager, toasts: details?.toasts)
            } isTargeted: { isOverItems = $0 }
            .onDrop(of: [.fileURL], isTargeted: $isOverFiles) { providers in
                guard !providers.isEmpty else { return false }
                browser.importProviders(
                    providers, to: browser.fileDropTarget(onCollection: collection, in: library), in: library, order: order,
                    undoManager: undoManager, toasts: details?.toasts)
                return true
            }
            .onChange(of: isTargeted) { reports?.wrappedValue = isTargeted }
            .background {
                if reports == nil, isTargeted {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.045))
                }
            }
            .overlay {
                if reports == nil, isTargeted {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.34), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
    }
}
