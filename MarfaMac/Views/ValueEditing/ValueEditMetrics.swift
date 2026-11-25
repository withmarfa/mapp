import CoreGraphics

/// The numbers a value panel is drawn with, as the boards measure them: 28 point rows with 7 point corners, a section
/// header 27 points high, 5 points of padding, the 13 point font and 14 point corners, on the system's glass.
nonisolated enum ValueEditMetrics {
    static let rowHeight: CGFloat = 28
    static let rowRadius: CGFloat = 7
    static let padding: CGFloat = 5
    /// A section header: 11 point text with 7 points above it and 2 below.
    static let headerHeight: CGFloat = 27
    /// The space between two rows of a list.
    static let rowGap: CGFloat = 1
    static let textSize: CGFloat = 13
    static let panelRadius: CGFloat = 14
    /// The most a panel is tall at the default text size; a longer list scrolls.
    static let tallest: CGFloat = 520
    /// The most rows a list shows at once; a longer one scrolls.
    static let visibleRows = 10
    /// How tall the type list is before it scrolls, as the board draws it: eleven rows and a line, the last row cut off.
    static let typeListHeight: CGFloat = 312
    /// The space between the value and its panel.
    static let gap: CGFloat = 4
    /// A typed value's panel is as wide as the value, within these.
    static let widthFloor: CGFloat = 220
    static let widthCeiling: CGFloat = 320
    /// A chip in the find field: 22 points high with the field's 7 point corners, in a line of 28.
    static let chipHeight: CGFloat = 22
    static let fieldLine: CGFloat = 28
    /// The most lines of chips the find field shows before it scrolls.
    static let chipLines = 8

    /// The least and most a panel is wide for what it holds, at the default text size: a list is as wide as its longest
    /// row, a calendar as wide as its seven days. A typed value has none; its panel follows the value.
    static func widthBounds(for kind: ValueEditKind) -> ClosedRange<CGFloat>? {
        switch kind {
        case .date: 212...212
        case .location: 360...360
        case .eventTime: 262...262
        case .entries: 300...340
        case .yesNo: 160...200
        case .tags: 270...270
        case .words: 194...273
        case .people: 216...308
        case .status: 250...300
        case .choice: 170...260
        case .type: 230...264
        case .relation: 210...210
        case .text, .number: nil
        }
    }
}
