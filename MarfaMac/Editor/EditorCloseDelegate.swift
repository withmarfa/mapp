import AppKit

/// SwiftUI owns the window delegate; forward its other callbacks while awaiting a safe editor flush. A window's typed
/// titles are saved first, with or without an editor (`WindowTitleDrafts`).
final class EditorCloseDelegate: NSObject, NSWindowDelegate {
    nonisolated(unsafe) private weak var previous: (any NSWindowDelegate)?
    private weak var editor: EditorController?
    /// Whether every title typed in the window is saved; a refused one has been told.
    private let saveTitles: () -> Bool
    private(set) weak var window: NSWindow?
    private(set) var awaiting = false
    private var approved = false

    convenience init(editor: EditorController, window: NSWindow) {
        self.init(window: window) { [weak editor] in editor?.saveTitles(tellingRefusal: true) != false }
        self.editor = editor
    }

    init(window: NSWindow, saveTitles: @escaping () -> Bool) {
        self.saveTitles = saveTitles
        self.window = window
        previous = window.delegate
        super.init()
        window.delegate = self
    }

    func detach() {
        if let window, window.delegate === self { window.delegate = previous }
    }

    isolated deinit { detach() }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if approved {
            approved = false
            return previous?.windowShouldClose?(sender) != false
        }
        guard previous?.windowShouldClose?(sender) != false else { return false }
        // A title typed in this window and refused would be lost with it.
        guard saveTitles() else { return false }
        // A hand-over still under way, as just after the item was left, holds the last edit of an item no longer
        // on the page; once the window goes, a quit no longer waits on its editor.
        guard let editor, editor.hasItem || editor.isFlushing else { return true }
        guard !awaiting else { return false }
        awaiting = true
        editor.flush(leaving: true) { [weak self, weak sender] kept in
            guard let self else { return }
            self.awaiting = false
            guard kept, let sender else { return }
            self.approved = true
            sender.performClose(nil)
            self.approved = false
        }
        return false
    }

    nonisolated override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || previous?.responds(to: selector) == true
    }

    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        previous?.responds(to: selector) == true ? previous : super.forwardingTarget(for: selector)
    }
}
