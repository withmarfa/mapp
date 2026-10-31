import CoreGraphics

/// What a column keeps across the window mounting its split view afresh, which drops the views' own state: the
/// sidebar's, and the list's, table's or gallery's. It is kept by the window's `Browser`, above that boundary, and the
/// new column starts from it so its first frame is the last one's. It is not observed: reading it never draws
/// anything again.
final class ColumnMemory {
    /// How far the list was scrolled, in the scroll view's own offset; nil until it has been.
    var scrollOffset: CGFloat?
    /// Said after the person scrolls, so a window can keep the position for the next launch.
    var scrolled: (() -> Void)?
    /// The column mounted now takes up `scrollOffset` again, as when a window is brought back from the last launch.
    var rearm: (() -> Void)?
    /// Whose `rearm` it is, so a column taken down does not remove the one that replaced it.
    var rearmOwner: ObjectIdentifier?

    /// Scrolls the column shown now, and any shown later, to `offset`.
    func restore(to offset: CGFloat) {
        scrollOffset = offset
        rearm?()
    }
    /// The foot's height and how far the list's content reaches below its bottom edge, which decide whether the foot
    /// draws its band (`ToolbarBand.isUnderFoot`).
    var footHeight: CGFloat = 0
    var hiddenBelow: CGFloat = 0

    func forget() {
        scrollOffset = nil
        footHeight = 0
        hiddenBelow = 0
    }
}
