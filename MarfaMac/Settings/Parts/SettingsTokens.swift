import AppKit
import SwiftUI

/// Every color, font and measure Settings draws with, named once, so a page never holds a literal and a theme can
/// replace them later. The parts read these; a page reads only the parts.
enum SettingsTokens {
    /// The colors of a page's tile in the sidebar and of a row's lead.
    enum Tone: CaseIterable, Hashable, Sendable {
        case gray, blue, indigo, amber, orange, purple, teal, green, pink, red

        /// Row and navigation tiles, shared by the App and Marfa boards. The sidebar uses `sidebarColor`.
        var color: Color {
            switch self {
            case .gray: rgb(0x8a8a90)
            case .blue: rgb(0x007aff)
            case .indigo: rgb(0x5856d6)
            case .amber: rgb(0xe0a800)
            case .orange: rgb(0xf08a00)
            case .purple: rgb(0xa650d8)
            case .teal: rgb(0x17a2b8)
            case .green: rgb(0x28a745)
            case .pink: rgb(0xe8437a)
            case .red: Color(nsColor: .systemRed)
            }
        }

        var sidebarColor: Color {
            switch self {
            case .gray: Color(nsColor: .systemGray)
            case .blue: rgb(0x1f6bf2) // Signal
            case .indigo: rgb(0x1a4fd6) // Cobalt
            case .amber: rgb(0xf5b316) // Marigold
            case .orange, .pink, .red: rgb(0xe4572e) // Adobe
            case .purple: rgb(0x111113) // Ink
            case .teal: rgb(0x0e9488) // Sea
            case .green: rgb(0x2e9e4f) // Leaf
            }
        }
    }

    /// A card: white with a hairline, never gray.
    static let card = adaptive(light: .white, dark: NSColor(white: 0.17, alpha: 1))
    static let cardEdge = adaptive(light: NSColor(white: 0, alpha: 0.144), dark: NSColor(white: 1, alpha: 0.144))
    static let cardShadow = Color.black.opacity(0.03)
    static let hairline = adaptive(light: NSColor(white: 0, alpha: 0.09), dark: NSColor(white: 1, alpha: 0.12))
    static let rule = adaptive(light: NSColor(white: 0, alpha: 0.098), dark: NSColor(white: 1, alpha: 0.098))
    /// The fill of a quiet control.
    static let buttonFill = adaptive(light: NSColor(white: 0, alpha: 0.06), dark: NSColor(white: 1, alpha: 0.12))
    /// A chosen row, card or table row: a soft gray, never blue.
    static let selection = adaptive(light: NSColor(white: 0, alpha: 0.07), dark: NSColor(white: 1, alpha: 0.1))
    /// Free space on a storage bar: the label ink at 7%, with the legend swatch edged at 22%.
    static let storageFree = adaptive(light: NSColor(white: 0, alpha: 0.059), dark: NSColor(white: 1, alpha: 0.059))
    static let storageFreeEdge = adaptive(light: NSColor(white: 0, alpha: 0.186), dark: NSColor(white: 1, alpha: 0.186))
    /// Where a row is under the pointer.
    static let hover = adaptive(light: NSColor(white: 0, alpha: 0.04), dark: NSColor(white: 1, alpha: 0.06))
    /// The fill of a field with accessories or of a read-only value.
    static let field = adaptive(light: .white, dark: NSColor(white: 0.12, alpha: 1))
    static let shortcutField = adaptive(light: .white, dark: NSColor(white: 0.23, alpha: 1))
    static let shortcutEdge = adaptive(light: NSColor(white: 0, alpha: 0.102), dark: NSColor(white: 1, alpha: 0.102))
    /// Tertiary ink for the recorder's action, with contrast against its field fill in both appearances.
    static let shortcutPlaceholder = adaptive(light: NSColor(white: 0.46, alpha: 1), dark: NSColor(white: 0.69, alpha: 1))
    static let shortcutClear = adaptive(light: NSColor(white: 0, alpha: 0.3), dark: NSColor(white: 1, alpha: 0.38))
    static let page = Color(nsColor: .windowBackgroundColor)
    static let errorRed = adaptive(light: NSColor(red: 0.78, green: 0.13, blue: 0.1, alpha: 1), dark: NSColor(red: 1, green: 0.42, blue: 0.38, alpha: 1))
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let primaryText = Color(nsColor: .labelColor)
    static let sidebarSelectedText = adaptive(light: NSColor(white: 0.13, alpha: 1), dark: NSColor(white: 0.9, alpha: 1))
    static let tileForeground = Color.white
    static let swatchEdge = Color.black.opacity(0.14)
    static let swatchDot = Color.white
    /// The swatch of a color the person makes, before they have made one.
    static let rainbow = AngularGradient(
        colors: [rgb(0xff3b30), rgb(0xffcc00), rgb(0x34c759), rgb(0x00c7be), rgb(0x007aff), rgb(0xaf52de), rgb(0xff2d55), rgb(0xff3b30)],
        center: .center)
    /// The accent the Mac is set to, which the first swatch of a color choice shows.
    static let systemAccent = Color(nsColor: .controlAccentColor)
    static let warning = Color(nsColor: .systemOrange)
    /// A healthy or sending status. The boards name this green in both appearances; the system green resolves lighter offscreen.
    static let ok = adaptive(
        light: NSColor(red: 52 / 255, green: 199 / 255, blue: 89 / 255, alpha: 1),
        dark: NSColor(red: 48 / 255, green: 209 / 255, blue: 88 / 255, alpha: 1))
    static let choiceEdge = Color.black.opacity(0.2)
    static let choiceSelectionRing = adaptive(light: NSColor(white: 0, alpha: 0.339), dark: NSColor(white: 1, alpha: 0.339))
    /// A focused control's ring is gray.
    static let focusRing = Color.primary.opacity(ChipLooks.defaults.focusRingOpacity)
    /// The scrim behind a centered sheet.
    static let scrim = Color.black.opacity(0.18)
    /// The shadow under a sheet.
    static let sheetShadow = Color.black.opacity(0.22)

    /// The miniature windows keep their own palette and scale independently of Settings.
    enum ThemePreview {
        struct Palette {
            let page: Color, sidebar: Color, text: Color, secondary: Color, tertiary: Color
            let sidebarSelection: Color, listSelection: Color, rule: Color
        }

        static let light = Palette(
            page: .white, sidebar: rgb(0xecedef), text: .black.opacity(0.82), secondary: .black.opacity(0.56),
            tertiary: .black.opacity(0.36), sidebarSelection: .black.opacity(0.098), listSelection: .black.opacity(0.07),
            rule: .black.opacity(0.055))
        static let dark = Palette(
            page: rgb(0x1e1e1e), sidebar: rgb(0x252533), text: .white.opacity(0.85), secondary: .white.opacity(0.56),
            tertiary: .white.opacity(0.36), sidebarSelection: .white.opacity(0.13), listSelection: .white.opacity(0.1),
            rule: .white.opacity(0.1))
        static let trafficLights = [rgb(0xff5f57), rgb(0xfebc2e), rgb(0x28c840)]
        static let trafficEdge = Color.black.opacity(0.12)
        static let note = rgb(0xffcc00)
        static let task = rgb(0x007aff)
        static let event = rgb(0xff3b30)

        static let scale: CGFloat = 0.5
        static let referenceWidth: CGFloat = 372
        static let sidebarWidth: CGFloat = 132
        static let sidebarTop: CGFloat = 40
        static let panelInset: CGFloat = 8
        static let trafficInset: CGFloat = 14
        static let trafficSize: CGFloat = 11
        static let trafficGap: CGFloat = 7
        static let sidebarRowHeight: CGFloat = 30
        static let sidebarRowGap: CGFloat = 1
        static let sidebarGroupGap: CGFloat = 10
        static let sidebarRadius: CGFloat = 8
        static let sidebarGlyph: CGFloat = 18
        static let sidebarLabelGap: CGFloat = 9
        static let listTop: CGFloat = 30
        static let listRowHeight: CGFloat = 56
        static let listRowInset: CGFloat = 10
        static let listGlyph: CGFloat = 16
        static let listTitleGap: CGFloat = 8
        static let listLineGap: CGFloat = 2
        static let listRadius: CGFloat = 10
        nonisolated static let splitTop: CGFloat = 0.56
        nonisolated static let splitBottom: CGFloat = 0.46
        static let titleFont = Font.system(size: 13, weight: .semibold)
        static let sidebarFont = Font.system(size: 13)
        static let detailFont = Font.system(size: 12)
    }

    /// The interface fonts of Settings. A page asks for these by role.
    enum Role: Hashable, Sendable {
        case title, line, sectionName, sectionLine, footer, small, mono, stateTitle, headTitle, pageHeader, usageFigure, sidebarBadge, largeGlyph, tableHeader, pathGlyph, chartAxis, chartTick
    }

    static func font(_ role: Role, scale: CGFloat = 1) -> Font {
        switch role {
        case .title: .system(size: 13 * scale)
        case .sidebarBadge: .system(size: 11 * scale, weight: .semibold)
        case .pageHeader: .system(size: 17 * scale, weight: .semibold)
        case .usageFigure: .system(size: 20 * scale, weight: .semibold)
        case .pathGlyph: .system(size: 12 * scale)
        case .chartAxis: .system(size: 11 * scale)
        case .chartTick: .system(size: 10.5 * scale)
        case .line, .sectionLine, .footer: .system(size: 12 * scale)
        case .sectionName: .system(size: 13 * scale, weight: .semibold)
        case .small: .system(size: 12 * scale)
        case .mono: .system(size: 12 * scale, design: .monospaced)
        case .stateTitle: .system(size: 13 * scale, weight: .semibold)
        case .largeGlyph: .system(size: 15 * scale)
        case .headTitle: .system(size: 15 * scale, weight: .semibold)
        case .tableHeader: .system(size: 11.5 * scale, weight: .semibold)
        }
    }

    /// The measures, in points at the default text size.
    enum Metric {
        /// The column's widest width: wider windows add room either side.
        static let column: CGFloat = 620
        static let windowWidth: CGFloat = 1200
        static let windowHeight: CGFloat = 900
        static let windowMinWidth: CGFloat = 760
        static let windowMinHeight: CGFloat = 480
        /// How far a page's centred state sits below a third of the pane, so its title sits where S35 draws it.
        static let pageStateDrop: CGFloat = 9
        /// How wide a state's words may run before they wrap; a state's line is worded to fit it on one.
        static let stateMeasure: CGFloat = 420
        static let sidebarWidth: CGFloat = 240
        static let rowHeight: CGFloat = 44
        static let rowHeightWithLine: CGFloat = 56
        static let rowHeightCompact: CGFloat = 36
        /// A row in a sheet's list of choices with a title and a line, such as a restore point.
        static let choiceRowHeight: CGFloat = 48
        /// The gap between a choice row's title and its line.
        static let choiceLineGap: CGFloat = 2
        /// A choice row's leading and trailing inset inside its list.
        static let choiceRowInset: CGFloat = 12
        /// The space above and below a standard row's words beyond the row's own padding, which a line that wraps keeps by
        /// growing the row: a row of one line is then exactly its height.
        static let rowTextPadding: CGFloat = 1
        /// A card's side margin, where a row's text starts when it has no lead.
        static let inset: CGFloat = 16
        /// The lead column, in which a tile, a symbol or a mark sits; text starts after it, at 52.
        static let leadColumn: CGFloat = 24
        static let textInset: CGFloat = 52
        /// An input at a row's end: a pop-up, a text field, a shortcut field and a slider.
        static let controlWidth: CGFloat = 160
        /// A number's field, with its unit after it.
        static let numberWidth: CGFloat = 72
        /// A field's height, which the system draws and a read-only value is as tall as.
        static let controlHeight: CGFloat = 28
        static let smallControlHeight: CGFloat = 24
        static let fieldAccessoryInset: CGFloat = 8
        static let popUpMinimumWidth: CGFloat = 120
        static let popUpLabelInset: CGFloat = 24
        static let smallNumberWidth: CGFloat = 64
        static let controlScaleForLarge: CGFloat = 1.3
        static let headerChoicePadding: CGFloat = 4
        /// A table that is a page: its side margin, and the height of the bar above its columns and of the foot below them.
        static let pageTableInset: CGFloat = 24
        static let pageTableBar: CGFloat = 48
        /// A log table's count bar and foot, which sit closer than a table with selection and actions.
        static let logTableBar: CGFloat = 34
        static let logTableFoot: CGFloat = 44
        /// The words of a state: the symbol's size, and the gaps between its symbol, title, line and action, on a page and in a card.
        enum State {
            static let glyph: CGFloat = 29
            static let spacing: CGFloat = 8
            static let symbolGap: CGFloat = 6
            static let actionGap: CGFloat = 12
            static let cardSpacing: CGFloat = 4
            static let cardSymbolGap: CGFloat = 4
            static let cardActionGap: CGFloat = 16
        }
        /// A table's header band.
        static let tableHeader: CGFloat = 30
        /// A table row's height: in a section, and on a page of its own, which draws them closer.
        static let tableRow: CGFloat = 34
        static let tablePreviewThreshold = 50
        static let tablePreviewCount = 20
        static let tableFooterHeight: CGFloat = 40
        static let sectionTableInset: CGFloat = 12
        static let sectionTableColumnGap: CGFloat = 10
        static let typeTableIndent: CGFloat = 20
        static let pageTableRow: CGFloat = 30
        /// The space above and below a table row's cells, which a cell that wraps keeps by growing the row.
        static let tableCellPadding: CGFloat = 7
        static let cardRadius: CGFloat = 12
        static let cardEdgeWidth: CGFloat = 0.5
        static let cardShadowRadius: CGFloat = 2
        static let cardShadowDrop: CGFloat = 1
        static let cardRuleWidth: CGFloat = 0.5
        static let controlRadius: CGFloat = 7
        static let shortcutRadius: CGFloat = 6
        static let shortcutEdgeWidth: CGFloat = 1
        static let shortcutClearSize: CGFloat = 14
        static let shortcutClearInset: CGFloat = 7
        static let shortcutKeysInset: CGFloat = 26
        static let shortcutPlaceholderInset: CGFloat = 8
        static let shortcutMinimumLabelScale: CGFloat = 0.75
        static let tile: CGFloat = 24
        static let avatarInitialsMinimumScale: CGFloat = 0.35
        /// A tile's radius and symbol box, as shares of its side.
        static let tileRounding: CGFloat = 0.27
        static let tileGlyph: CGFloat = 0.75
        /// A well's symbol or mark, as a share of its side: 12 points in the 24 point well.
        static let wellGlyph: CGFloat = 0.5
        static let headTile: CGFloat = 44
        /// A search field at a list's trailing edge, 28 points tall, and the button beside it that changes what it searches by.
        static let searchWidth: CGFloat = 200
        static let searchSpacing: CGFloat = 8
        /// The sidebar's tile.
        static let sidebarTile: CGFloat = 20
        static let sidebarTileGlyph: CGFloat = 0.63
        static let sidebarRowLeading: CGFloat = 2
        static let sidebarFooterInset: CGFloat = 18
        static let sidebarFooterPadding: CGFloat = 10
        static let sidebarFooterBottom: CGFloat = 14
        static let sidebarFooterGap: CGFloat = 4
        static let sidebarBadgeSize: CGFloat = 18
        static let sidebarBadgePadding: CGFloat = 5
        static let tileEdgeWidth: CGFloat = 0.5
        /// A color swatch and the dot that marks the chosen one, and the space between swatches.
        static let swatch: CGFloat = 18
        static let swatchDot: CGFloat = 6
        static let swatchSpacing: CGFloat = 9
        static let swatchEdgeWidth: CGFloat = 0.5
        static let swatchDividerHeight: CGFloat = 16
        static let swatchDividerWidth: CGFloat = 1
        static let swatchDividerInset: CGFloat = 1
        static let iconChoiceSpacing: CGFloat = 8
        /// Compensates for the transparent margin built into the icon assets.
        static let iconChoiceScale: CGFloat = 1.25
        static let iconChoiceRingOutset: CGFloat = 3
        /// How much of the system's color well shows over a swatch that stands for it: none to the eye, all to the pointer.
        static let invisibleWell: Double = 0.02
        /// A choice tile's picture is wider than tall, as the board draws it: 186 by 104 in the column.
        static let choiceAspect: CGFloat = 186 / 104
        static let choiceGap: CGFloat = 14
        static let choiceTitleGap: CGFloat = 7
        static let choiceBottom: CGFloat = 12
        static let choiceRadius: CGFloat = 8
        static let choiceEdgeWidth: CGFloat = 0.5
        static let choiceRingGap: CGFloat = 2
        static let choiceRingWidth: CGFloat = 2.5
        /// The space above and below the rows a preview card draws.
        static let previewCardInset: CGFloat = 4
        /// The side margin of a picture of rows (a density tile) and the thickness of the rule between its rows.
        static let previewRowSide: CGFloat = 10
        static let ruleThickness: CGFloat = 1
        /// The space between a table's columns.
        static let tableColumnGap: CGFloat = 12
        /// The gap between buttons or a value and a button at a row's end, and between a head card and what sits under it.
        static let buttonGap: CGFloat = 8
        static let cardGap: CGFloat = 10
        /// A page's side margin and an empty card's top and bottom padding.
        static let pageSide: CGFloat = 24
        static let emptyCardPadding: CGFloat = 28
        /// A status dot, the space after it, and the small lock before a value that is set elsewhere with its glyph size.
        static let statusDot: CGFloat = 7
        static let dotGap: CGFloat = 6
        static let lockGlyph: CGFloat = 10
        static let lockGap: CGFloat = 5
        static let lockedTileOpacity = 0.45
        static let pathGlyphGap: CGFloat = 4
        static let pageHeaderTop: CGFloat = 4
        static let pageHeaderNameHeight: CGFloat = 22
        static let pageHeaderAddressHeight: CGFloat = 18
        static let tabGap: CGFloat = 2
        static let tabPadding: CGFloat = 11
        static let tabHeight: CGFloat = 28

        enum Usage {
            static let plotHeight: CGFloat = 150
            static let maxBarWidth: CGFloat = 44
            static let barWidthRatio: CGFloat = 0.46
            static let bottomPadding: CGFloat = 14
            static let chartTop: CGFloat = 6
            static let chartGap: CGFloat = 8
            static let legendColumnGap: CGFloat = 16
            static let legendRowGap: CGFloat = 6
            static let legendTop: CGFloat = 6
            static let swatchSize: CGFloat = 8
            static let swatchRadius: CGFloat = 2
            static let storageHeight: CGFloat = 12
            static let storageGap: CGFloat = 2
            static let storageLegendGap: CGFloat = 12
            /// The top of the uppermost segment, and the room the trailing counts take beside the plot.
            static let barCornerRadius: CGFloat = 3
            static let axisGutter: CGFloat = 34
            static let axisLabelGap: CGFloat = 8
        }
        /// The mark before a status group.
        static let statusMark: CGFloat = 14
        /// A word chip (a status word): its height, corner, side padding, the space between chips and the small add button.
        static let chipHeight: CGFloat = 22
        static let chipRadius: CGFloat = 6
        static let chipPadding: CGFloat = 7
        static let chipGap: CGFloat = 6
        /// The room a word being typed takes, and the widest a chip grows before its text is cut.
        static let chipFieldWidth: CGFloat = 96
        static let chipMaxWidth: CGFloat = 160
        /// The least a row that holds a long text under its title is tall, and the room between the title and the text.
        static let stackGap: CGFloat = 6
        /// A table's column widths, by what they hold, and its action and check columns.
        enum Column {
            static let state: CGFloat = 70
            static let day: CGFloat = 90
            /// A count in a usage table. Other tables keep `day`.
            static let number: CGFloat = 80
            static let label: CGFloat = 110
            static let address: CGFloat = 130
            static let time: CGFloat = 150
            static let who: CGFloat = 200
            static let setting: CGFloat = 255
            static let action: CGFloat = 88
            static let check: CGFloat = 18
        }
        /// The space between a page's sections, and above and below its column.
        static let pageSpacing: CGFloat = 26
        /// A section's name is at least this tall, with the name at its foot, and the gap between that and its card, so a name
        /// alone sits nearer its card than the section above it, and a name with a line starts higher.
        static let sectionHeader: CGFloat = 22
        static let sectionGap: CGFloat = 8
        /// The space between a card and the row of buttons under it, which sit nearer than a section does.
        static let barGap: CGFloat = 14
        /// Below the toolbar: a head card sits 62 points under the window's top, as the boards draw.
        static let pageTop: CGFloat = 10
        /// More room above the first section of a page when it opens with its name and a line under it (the boards put the card
        /// 105.5 points under the window's top).
        static let firstHeaderWithLineInset: CGFloat = 2
        static let pageBottom: CGFloat = 40
        static let footerLineHeight: CGFloat = 16
        /// The sheet that asks about changes that wait: its stack spacing, a change's spacing, padding and radius, and
        /// the tallest its list of texts grows.
        static let sheetSpacing: CGFloat = 12
        static let sheetListSpacing: CGFloat = 10
        static let sheetChangeSpacing: CGFloat = 4
        static let sheetChangePadding: CGFloat = 8
        static let sheetChangeRadius: CGFloat = 6
        static let sheetListMaxHeight: CGFloat = 220
        /// The space round a sheet's fields: above and below them, between them (the form's gap is for a sheet with more to ask),
        /// between its title and line, and between a field and its label. And its corners and shadow.
        static let sheetGap: CGFloat = 16
        static let sheetFieldGap: CGFloat = 12
        static let sheetFormGap: CGFloat = 16
        static let sheetHeadSpacing: CGFloat = 3
        static let sheetLabelSpacing: CGFloat = 5
        static let sheetRadius: CGFloat = 18
        static let sheetShadowRadius: CGFloat = 24
        static let sheetShadowDrop: CGFloat = 8
        /// The most lines a copy of an unsent text shows in a sheet.
        static let sheetTextLines = 8
        /// A sheet's width, its wide width, its side and top padding, and the room it keeps from the window's edge.
        static let sheetWidth: CGFloat = 440
        static let sheetWideWidth: CGFloat = 560
        static let sheetPadding: CGFloat = 20
        static let sheetEdgeMargin: CGFloat = 24
        /// How far a section's name sits from the card's edge inside a sheet, which is nearer than on a page.
        static let sheetSectionInset: CGFloat = 4
    }

    private static func rgb(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

extension EnvironmentValues {
    /// The interface text size's scale, which the window sets from the person's choice.
    @Entry var settingsTextScale: CGFloat = 1
}

private struct SettingsFont: ViewModifier {
    let role: SettingsTokens.Role
    @Environment(\.settingsTextScale) private var scale

    func body(content: Content) -> some View {
        content.font(SettingsTokens.font(role, scale: scale))
    }
}

extension Text {
    /// A command or other code inside a sentence, in the monospaced version of the font round it, so it follows the text size.
    static func settingsCode(_ code: String) -> Text { Text(verbatim: code).monospaced() }
}

extension View {
    /// Sets the interface font for `role`, at the person's text size.
    func settingsFont(_ role: SettingsTokens.Role) -> some View { modifier(SettingsFont(role: role)) }
}
