import SwiftUI

/// What the menu bar can do to the container chosen in the index in front, which its table's row menu offers too: each
/// action is nil where the chosen row, or the page, has none (a collection has no mark to choose, a source cannot be
/// deleted, and with nothing chosen there is nothing to act on).
struct IndexActions {
    var rename: (() -> Void)?
    var chooseMark: (() -> Void)?
    var delete: (() -> Void)?
}

extension FocusedValues {
    @Entry var indexActions: IndexActions?
}
