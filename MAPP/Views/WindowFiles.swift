import QuickLook
import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Makes the window take files: dropped from Finder anywhere in it, or imported from a nearby device by the File
    /// menu's Import from iPhone, each becoming an item through `Browser.importFiles`; and shows Quick Look for the
    /// browser's request.
    func handlesFiles(in browser: Browser, order: NoteOrder) -> some View {
        modifier(WindowFiles(browser: browser, order: order))
    }

    /// Space shows the selected items in Quick Look, from a list that has the keyboard.
    func quickLooksOnSpace(_ browser: Browser) -> some View {
        modifier(QuickLookOnSpace(browser: browser))
    }

    /// Makes the view take files and items dropped on it as the collection `id`'s: items join it, and files are
    /// added to the library and join it. A nil `id` leaves the view as it is, so a row that is not a collection can carry it.
    @ViewBuilder
    func dropsInto(collection id: ItemID?, browser: Browser, order: NoteOrder) -> some View {
        if let id {
            modifier(CollectionDrop(collection: id, browser: browser, order: order))
        } else {
            self
        }
    }
}

private struct WindowFiles: ViewModifier {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    let browser: Browser
    let order: NoteOrder
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                take(providers)
            }
            .importsItemProviders(FileIntake.deviceTypes) { providers in
                take(providers)
            }
            .overlay {
                if isTargeted {
                    Rectangle()
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .allowsHitTesting(false)
                }
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

    private func take(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        browser.importProviders(providers, in: library, order: order, undoManager: undoManager)
        return true
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
    let collection: ItemID
    let browser: Browser
    let order: NoteOrder
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .dropDestination(for: ItemReference.self) { references, _ in
                library.addToCollection(Set(references.map(\.id)), collection, undoManager: undoManager)
            } isTargeted: { isTargeted = $0 }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                guard !providers.isEmpty else { return false }
                browser.importProviders(providers, into: collection, in: library, order: order, undoManager: undoManager)
                return true
            }
            .background {
                if isTargeted { RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.25)) }
            }
    }
}
