import Foundation

/// How tall one hour is in the calendar's week, which a pinch on the trackpad changes. One value in the defaults, synced
/// through the Marfa (`PreferencesMap`).
nonisolated enum CalendarHourHeight {
    static let key = "calendarHourHeight"
    /// The least and the most an hour may be, in points.
    static let range: ClosedRange<CGFloat> = 24...160
    /// An hour's height until the person pinches.
    static let standard: CGFloat = 59

    /// `height` held to `range`; anything that is not a number is the standard height.
    static func clamped(_ height: CGFloat) -> CGFloat {
        guard height.isFinite else { return standard }
        return min(max(height, range.lowerBound), range.upperBound)
    }

    /// The height a pinch reaches: the height the pinch began at, times its magnification, held to `range`.
    static func pinched(from height: CGFloat, magnification: CGFloat) -> CGFloat {
        guard magnification.isFinite, magnification > 0 else { return clamped(height) }
        return clamped(height * magnification)
    }

    /// Where the grid scrolls to when the hour height changes from `old` to `new`, so the point `gridY` points down the
    /// grid, which is the hour under the pointer, stays where it is on screen. `offset` is how far the grid has scrolled.
    static func offset(keeping gridY: CGFloat, scrolled offset: CGFloat, from old: CGFloat, to new: CGFloat) -> CGFloat {
        guard old > 0 else { return offset }
        return offset + gridY * (new / old - 1)
    }

    /// The fewest minutes a block is taken to take up when blocks are set side by side: what 30 minutes is at the standard
    /// height, as points, so a short event keeps the room its drawn block needs at any height.
    static func shortestBlock(at height: CGFloat) -> Int {
        let points = CGFloat(CalendarLayout.shortestBlock) * standard / 60
        return Int((points * 60 / clamped(height)).rounded(.up))
    }
}
