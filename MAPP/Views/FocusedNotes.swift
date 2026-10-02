import SwiftUI
import Observation

/// The notes the frontmost window is showing, and that window's undo manager, so the menu bar acts on them.
struct FocusedNotes {
    let ids: Set<Note.ID>
    let undoManager: UndoManager?
}

extension FocusedValues {
    /// The main window in front, for commands that change what it shows.
    @Entry var browser: Browser?
    @Entry var detailsPresentation: DetailsPresentation?
    @Entry var focusedNotes: FocusedNotes?
    /// The editor of the window in front, for the Format menu.
    @Entry var editor: EditorController?
    /// Marfa Types, while the window in front shows it, for Back and Forward.
    @Entry var marfaTypes: MarfaTypesPage?
}

/// Presentation belongs to a window, so menu and toolbar actions share it without changing other windows.
@Observable
final class DetailsPresentation {
    var isPresented = false
}
