import CoreGraphics

/// What the sidebar keeps across the window mounting its split view afresh, which drops the views' own state. It is
/// kept by the window's `Browser`, above that boundary, and the new sidebar starts from it so its first frame is the
/// last one's. It is not observed: reading it never draws anything again.
final class SidebarMemory {
    /// How far the list was scrolled, in the scroll view's own offset; nil until it has been.
    var scrollOffset: CGFloat?
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
