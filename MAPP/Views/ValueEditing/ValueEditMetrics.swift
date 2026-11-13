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
    /// The most a panel is tall at the default text size; a longer list scrolls.
    static let tallest: CGFloat = 520
    /// The most rows a list shows at once; a longer one scrolls.
    static let visibleRows = 10
    /// The space between the value and its panel.
    static let gap: CGFloat = 4
    /// A typed value's panel is as wide as the value, within these.
    static let widthFloor: CGFloat = 220
    static let widthCeiling: CGFloat = 320

    /// The least and most a panel is wide for what it holds, at the default text size: a list is as wide as its longest
    /// row, a calendar as wide as its seven days. A typed value has none; its panel follows the value.
    static func widthBounds(for kind: ValueEditKind) -> ClosedRange<CGFloat>? {
        switch kind {
        case .date: 240...240
        case .location: 340...340
        case .tags, .words: 194...273
        case .people: 216...308
        case .status, .choice: 192...260
        case .type: 200...264
        case .parent: 200...264
        case .text, .number: nil
        }
    }
}
