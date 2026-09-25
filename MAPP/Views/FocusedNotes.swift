import SwiftUI

/// The notes the frontmost window is showing, and that window's undo manager, so the menu bar acts on them.
struct FocusedNotes {
    let ids: Set<Note.ID>
    let undoManager: UndoManager?
}

extension FocusedValues {
    /// The main window in front, for commands that change what it shows.
    @Entry var browser: Browser?
    @Entry var focusedNotes: FocusedNotes?
}
