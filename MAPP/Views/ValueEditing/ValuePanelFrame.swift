import CoreGraphics

/// Where a value panel goes for the value it edits, in screen coordinates (origin at the bottom left): under the
/// value and starting at its leading edge, or ending at its trailing edge where the value is narrower than the panel,
/// as in the sidebar. It flips above where there is no room below, and is as tall as the content unless the room left
/// is shorter, in which case the list scrolls.
nonisolated enum ValuePanelFrame {
    struct Placement: Equatable {
        var frame: CGRect
        var isAbove: Bool
    }

    /// The least height worth opening a panel for, so a list is not squeezed to a sliver where both sides are tight.
    static let leastHeight: CGFloat = 96

    static func placement(
        anchor: CGRect, visible: CGRect, contentHeight: CGFloat, floor: CGFloat, ceiling: CGFloat, gap: CGFloat
    ) -> Placement {
        let width = min(max(anchor.width, floor), max(floor, ceiling), visible.width)
        let leading = width > anchor.width ? anchor.maxX - width : anchor.minX
        let x = min(max(leading, visible.minX), visible.maxX - width)
        let below = anchor.minY - gap - visible.minY
        let above = visible.maxY - (anchor.maxY + gap)
        let wanted = max(contentHeight, 1)
        let isAbove: Bool
        let height: CGFloat
        if wanted <= below {
            (isAbove, height) = (false, wanted)
        } else if wanted <= above {
            (isAbove, height) = (true, wanted)
        } else {
            isAbove = above > below
            height = max(min(isAbove ? above : below, wanted), min(leastHeight, wanted))
        }
        let y = isAbove ? anchor.maxY + gap : anchor.minY - gap - height
        return Placement(frame: CGRect(x: x, y: max(y, visible.minY), width: width, height: min(height, visible.height)), isAbove: isAbove)
    }
}
