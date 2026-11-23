/// Holds a window's editor, made the first time the window's view reads it.
///
/// SwiftUI makes a view's value again each time its parent updates and keeps only the state it stored first, so an
/// editor made in a view's initializer would build a web view, and start a page process, for every parent update.
/// A view keeps this slot in `@State` and reads the editor in `body`, which SwiftUI runs only for the view it keeps.
final class EditorSlot {
    /// The editor, once the view has read it.
    private(set) var made: EditorController?

    /// The editor, made by `make` if there is none yet.
    func editor(_ make: () -> EditorController) -> EditorController {
        if let made { return made }
        let editor = make()
        made = editor
        return editor
    }
}
