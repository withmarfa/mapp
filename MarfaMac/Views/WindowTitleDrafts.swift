import AppKit
import SwiftUI

/// A window's typed titles, kept through every flush as a page's own are: a close waits for them (`EditorCloseDelegate`),
/// and a quit and a change of library try them first (`EditorController.flushAll`). A window showing only a file makes
/// no editor, and a main window's editor is not in the window until a text item has been shown, so the titles cannot
/// rely on the editor for this.
@MainActor
final class WindowTitleDrafts {
    /// Every window that holds titles, so a flush reaches those of a window with no editor.
    static let open = NSHashTable<WindowTitleDrafts>.weakObjects()

    private(set) weak var drafts: DetailsPresentation?
    private weak var library: (any ItemLibrary)?
    private weak var window: NSWindow?
    private var closeDelegate: EditorCloseDelegate?
    /// Shows the item whose title was refused, which the window may have moved away from.
    private var showRefused: (ItemID) -> Void = { _ in }

    /// Keeps `drafts` for `window`, read from `library`. A window seen again keeps the close delegate it had, since
    /// another may have been set over it.
    func keep(_ drafts: DetailsPresentation, of window: NSWindow?, in library: any ItemLibrary, showRefused: @escaping (ItemID) -> Void) {
        self.drafts = drafts
        self.library = library
        self.showRefused = showRefused
        Self.open.add(self)
        guard let window, window !== self.window else { return }
        self.window = window
        closeDelegate = EditorCloseDelegate(window: window) { [weak self] in self?.save(tellingRefusal: true) ?? true }
    }

    /// Whether every title is saved; a refused one brings the window forward with its item.
    func save(tellingRefusal: Bool) -> Bool {
        guard let drafts, let library else { return true }
        return drafts.saveTitles(in: library, undoManager: window?.undoManager, tellingRefusal: tellingRefusal) { [weak self] id in
            self?.window?.makeKeyAndOrderFront(nil)
            self?.showRefused(id)
        }
    }

    /// The window has gone, as when its item was deleted or its library changed. A title still typed goes back to the
    /// person, since nothing else holds it.
    func windowWent() {
        if let drafts, let library { drafts.handBackTitles(in: library) }
        Self.open.remove(self)
    }
}

extension View {
    /// Keeps the window's typed titles through its close, a quit and a change of library (`WindowTitleDrafts`).
    func keepsTitleDrafts(_ drafts: DetailsPresentation, showRefused: @escaping (ItemID) -> Void = { _ in }) -> some View {
        modifier(TitleDraftsKeeping(drafts: drafts, showRefused: showRefused))
    }
}

private struct TitleDraftsKeeping: ViewModifier {
    @CurrentLibrary private var library
    @State private var keeper = WindowTitleDrafts()
    @State private var window: NSWindow?
    let drafts: DetailsPresentation
    let showRefused: (ItemID) -> Void

    func body(content: Content) -> some View {
        content
            .background { WindowReader(window: $window) }
            .onChange(of: WindowKey(window: window, library: ObjectIdentifier(library)), initial: true) {
                keeper.keep(drafts, of: window, in: library, showRefused: showRefused)
            }
            .onAppear { keeper.keep(drafts, of: window, in: library, showRefused: showRefused) }
            .onDisappear { keeper.windowWent() }
    }

    private struct WindowKey: Equatable {
        let window: NSWindow?
        let library: ObjectIdentifier
        static func == (a: Self, b: Self) -> Bool { a.window === b.window && a.library == b.library }
    }
}
