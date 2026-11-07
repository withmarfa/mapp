import CoreGraphics

/// The numbers a value panel is drawn with: a system menu as macOS 27 measures one (24 point rows, a section header the
/// same, 5 points of padding, the 13 point menu font), on the system's glass.
nonisolated enum ValueEditMetrics {
    static let rowHeight: CGFloat = 24
    static let rowRadius: CGFloat = 6
    static let padding: CGFloat = 5
    static let headerHeight: CGFloat = 24
    static let textSize: CGFloat = 13
    static let panelRadius: CGFloat = 12
    /// The space between the value and its panel.
    static let gap: CGFloat = 4
    /// The panel is as wide as the value, within these.
    static let widthFloor: CGFloat = 220
    static let widthCeiling: CGFloat = 320
}
