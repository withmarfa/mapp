import CoreGraphics

/// How the calendar's corner buttons fit the room the content has.
nonisolated enum CalendarCorner {
    /// The content width, in points, under which the Week or Month choice folds into one button with a menu. The
    /// segmented control and the other three buttons need about 380 points; below this the corner would crowd the
    /// week's day columns and the toast.
    static let foldsBelow: CGFloat = 860

    /// Whether Week or Month is one button with a menu rather than a segmented control, for content `width` points wide.
    static func foldsScale(forWidth width: CGFloat) -> Bool { width < foldsBelow }
}
