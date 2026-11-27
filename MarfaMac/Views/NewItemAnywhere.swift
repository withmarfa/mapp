import AppKit
import SwiftUI

/// The new-item line over another app, for the any-app New Item shortcut: a floating panel in the upper third of the
/// screen with the pointer that never makes the app active, so the other app keeps its place in front and has the
/// keyboard back as soon as the line closes. It makes items in the open library (`Libraries.current`) through a browser
/// of its own, with its own undo manager, and keeps what is typed as every new item does (`NewItemDrafts`): a draft
/// left in it is the next line's, here or in a window.
@MainActor
final class NewItemAnywhere {
    static let shared = NewItemAnywhere()

    private var panel: NSPanel?
    private var browser: Browser?
    private var library: (any ItemLibrary)?
    private let undoManager = UndoManager()
    /// The app in front when the line opened, which has the keyboard back when it closes.
    private var previous: NSRunningApplication?

    /// Opens the line over whatever app is in front, or brings it back where it is open already. With no library
    /// loaded, it brings the app forward instead, which shows why.
    func show(in libraries: Libraries) {
        guard let library = libraries.current, library.isLoaded, QuickAdd.isAvailable(in: library) else {
            NSApp.activate()
            return
        }
        if let panel, panel.isVisible, let current = self.library, current === library {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        close()
        let front = NSWorkspace.shared.frontmostApplication
        previous = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        let browser = Browser()
        browser.opensFoundElsewhere = { [weak library] ids in
            NSApp.activate()
            guard let library, let window = FrontBrowser.shared.last, window.isShowing(library) else { return ids }
            return await window.openFound(ids, in: library, order: ItemOrder())
        }
        browser.openNewItem(form: .line, in: library)
        guard browser.quickAdd.draft != nil else { return }
        self.browser = browser
        self.library = library
        let root = NewItemAnywhereRoot(browser: browser, library: library, undoManager: undoManager) { [weak self] in
            self?.close()
        } opensItem: { [weak self] id, typeID in
            self?.openInApp(id, typeID: typeID, in: libraries)
        } toTextForm: { [weak self] in
            self?.handOverToTextForm(in: library)
        }
        .environment(\.library, library)
        .environment(libraries)
        .environment(libraries.host)
        .environment(libraries.shortcuts)
        .interfaceTextStyle()
        .appAccent()
        let panel = LinePanel(contentRect: NSRect(x: 0, y: 0, width: 712, height: 400))
        panel.contentView = NSHostingView(rootView: root)
        place(panel)
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    /// Puts the line away. A draft with something typed stays kept for the next line. The other app has the keyboard
    /// back only where the line still had it and that app is still the one in front (`returnsFocus`).
    func close(returningFocus: Bool = true) {
        guard let panel else { return }
        let returns = returningFocus && Self.returnsFocus(
            panelIsKey: panel.isKeyWindow, previous: previous?.processIdentifier,
            front: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        if let browser, let library {
            browser.putAwayQuickAdd()
            browser.quickAdd.leave(because: .closed, telling: library.notices)
            browser.giveUpNewItems(because: .windowLeft)
        }
        panel.orderOut(nil)
        self.panel = nil
        browser = nil
        library = nil
        undoManager.removeAllActions()
        if returns { previous?.activate() }
        previous = nil
    }

    /// Whether putting the line away gives the keyboard back to the app it opened over: only while the line held the
    /// keyboard, so never after the person went elsewhere, and only while that app is still the one in front, so
    /// one they have since chosen is never pushed behind it.
    nonisolated static func returnsFocus(panelIsKey: Bool, previous: pid_t?, front: pid_t?) -> Bool {
        guard panelIsKey, let previous else { return false }
        return front == previous
    }

    /// Add and Open: the item opens in the app's front window, as the person set Open Items.
    private func openInApp(_ id: ItemID, typeID: String, in libraries: Libraries) {
        close(returningFocus: false)
        NSApp.activate()
        guard let window = FrontBrowser.shared.last, let library = libraries.current else { return }
        window.newItems.append(NewItem(
            id: id, typeID: typeID, library: library, caret: nil, isFile: QuickAdd.isFile(typeID, in: library.catalogue),
            opening: ItemOpening.stored(in: window.defaults)))
        window.finishNewItems(in: library)
    }

    /// Add Text, or a value the line has no place for: this line's own draft, kept as typed, opens in a window's text
    /// form (`FrontBrowser.hand`), never another draft a window holds.
    private func handOverToTextForm(in library: any ItemLibrary) {
        let handed = browser?.quickAdd.holdsContent == true ? browser?.quickAdd.entry : nil
        close(returningFocus: false)
        if let handed {
            FrontBrowser.shared.hand(handed, in: library)
        } else {
            // Nothing typed to hand over, so the window's text form opens as it would.
            NSApp.activate()
            FrontBrowser.shared.last?.openNewItem(form: .text, in: library)
        }
    }

    /// In the upper third of the screen the pointer is on, centred across it.
    private func place(_ panel: NSPanel) {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameTopLeftPoint(NSPoint(x: area.midX - size.width / 2, y: area.maxY - area.height / 6))
    }
}

/// A panel that takes the keyboard without making the app active, and floats over every app and space.
private final class LinePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        isOpaque = false
        // The line draws its own shadow.
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The line as the panel shows it: sized to itself, with the panel's own undo manager, finishing what it added as
/// the library takes it.
private struct NewItemAnywhereRoot: View {
    let browser: Browser
    let library: any ItemLibrary
    let undoManager: UndoManager
    let onClose: () -> Void
    let opensItem: (ItemID, String) -> Void
    let toTextForm: () -> Void

    var body: some View {
        Group {
            if browser.quickAdd.form == .line {
                NewItemLinePanel(
                    browser: browser, quickAdd: browser.quickAdd, undoManager: undoManager,
                    opensElsewhere: opensItem, onClose: onClose)
            } else {
                // Add Text, or a value the line has no place for, needs a window's text form.
                Color.clear.onAppear(perform: toTextForm)
            }
        }
        .padding(16)
        .fixedSize()
        .onChange(of: browser.isNewItemSettled(in: library)) { _, settled in
            if settled { browser.finishNewItems(in: library) }
        }
        .onChange(of: browser.quickAdd.isPresented) { _, presented in
            if !presented { onClose() }
        }
    }
}
