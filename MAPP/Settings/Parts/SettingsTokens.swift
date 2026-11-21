import AppKit
import SwiftUI

/// Every color, font and measure Settings draws with, named once, so a page never holds a literal and a theme can
/// replace them later. The parts read these; a page reads only the parts.
enum SettingsTokens {
    /// The colors of a page's tile in the sidebar and of a row's lead.
    enum Tone: CaseIterable, Hashable, Sendable {
        case gray, blue, indigo, amber, orange, purple, teal, green, pink, red

        /// The tile colors of the agreed sidebar (S9), which are not the system's: a deeper amber, indigo, green and teal.
        var color: Color {
            switch self {
            case .gray: Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
            case .blue: Color(red: 0, green: 122 / 255, blue: 255 / 255)
            case .indigo: Color(red: 104 / 255, green: 102 / 255, blue: 216 / 255)
            case .amber: Color(red: 225 / 255, green: 170 / 255, blue: 5 / 255)
            case .orange: Color(red: 240 / 255, green: 138 / 255, blue: 0)
            case .purple: Color(red: 166 / 255, green: 80 / 255, blue: 216 / 255)
            case .teal: Color(red: 24 / 255, green: 163 / 255, blue: 185 / 255)
            case .green: Color(red: 46 / 255, green: 170 / 255, blue: 75 / 255)
            case .pink: Color(red: 232 / 255, green: 67 / 255, blue: 122 / 255)
            case .red: Color(nsColor: .systemRed)
            }
        }
    }

    /// A card: white with a hairline, never gray.
    static let card = adaptive(light: .white, dark: NSColor(white: 0.17, alpha: 1))
    static let hairline = adaptive(light: NSColor(white: 0, alpha: 0.09), dark: NSColor(white: 1, alpha: 0.12))
    /// A row's rule: lighter than the card's edge.
    static let rule = adaptive(light: NSColor(white: 0, alpha: 0.07), dark: NSColor(white: 1, alpha: 0.09))
    /// The fill of a quiet control.
    static let buttonFill = adaptive(light: NSColor(white: 0, alpha: 0.06), dark: NSColor(white: 1, alpha: 0.12))
    /// A chosen row, card or table row: a soft gray, never blue.
    static let selection = adaptive(light: NSColor(white: 0, alpha: 0.07), dark: NSColor(white: 1, alpha: 0.1))
    /// Every other row of a section's table, a shade off the card's white.
    static let band = adaptive(light: NSColor(white: 0, alpha: 0.024), dark: NSColor(white: 1, alpha: 0.04))
    /// Where a row is under the pointer.
    static let hover = adaptive(light: NSColor(white: 0, alpha: 0.04), dark: NSColor(white: 1, alpha: 0.06))
    /// A value that can't be changed, in a field's place.
    static let field = adaptive(light: .white, dark: NSColor(white: 0.12, alpha: 1))
    static let page = Color(nsColor: .windowBackgroundColor)
    static let errorRed = adaptive(light: NSColor(red: 0.78, green: 0.13, blue: 0.1, alpha: 1), dark: NSColor(red: 1, green: 0.42, blue: 0.38, alpha: 1))
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let primaryText = Color(nsColor: .labelColor)
    /// The swatch of a color the person makes, before they have made one.
    static let rainbow = AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center)
    /// The accent the Mac is set to, which the first swatch of a color choice shows.
    static let systemAccent = Color(nsColor: .controlAccentColor)
    static let warning = Color(nsColor: .systemOrange)
    static let ok = Color(nsColor: .systemGreen)
    /// The one color a chosen choice's ring and a focused control's ring take: gray, never the accent.
    static let focusRing = Color.primary.opacity(0.26)
    /// The scrim behind a centered sheet.
    static let scrim = Color.black.opacity(0.18)
    /// The shadow under a sheet.
    static let sheetShadow = Color.black.opacity(0.22)

    /// The small windows a theme's tile draws: a sidebar of short bars and a page of lines, light and dark, which are the
    /// pictures of the choices and so do not follow the appearance the window is in.
    enum ThemePreview {
        static let lightPage = Color(nsColor: NSColor(white: 1, alpha: 1))
        static let lightSidebar = Color(nsColor: NSColor(srgbRed: 233 / 255, green: 234 / 255, blue: 237 / 255, alpha: 1))
        static let lightSidebarLine = Color(nsColor: NSColor(srgbRed: 202 / 255, green: 203 / 255, blue: 206 / 255, alpha: 1))
        static let lightLine = Color(nsColor: NSColor(white: 222 / 255, alpha: 1))
        static let darkPage = Color(nsColor: NSColor(white: 30 / 255, alpha: 1))
        static let darkSidebar = Color(nsColor: NSColor(srgbRed: 44 / 255, green: 44 / 255, blue: 54 / 255, alpha: 1))
        static let darkSidebarLine = Color(nsColor: NSColor(srgbRed: 86 / 255, green: 86 / 255, blue: 94 / 255, alpha: 1))
        static let darkLine = Color(nsColor: NSColor(white: 75 / 255, alpha: 1))
    }

    /// The interface fonts of Settings. A page asks for these by role.
    enum Role: Hashable, Sendable {
        case title, line, sectionName, sectionLine, footer, small, mono, stateTitle, headTitle, sidebar, largeGlyph, tableHeader
    }

    static func font(_ role: Role, scale: CGFloat = 1) -> Font {
        switch role {
        case .title, .sidebar: .system(size: 13 * scale)
        case .line, .sectionLine, .footer: .system(size: 11 * scale)
        case .sectionName: .system(size: 13 * scale, weight: .semibold)
        case .small: .system(size: 12 * scale)
        case .mono: .system(size: 12 * scale, design: .monospaced)
        case .stateTitle: .system(size: 13 * scale, weight: .semibold)
        case .largeGlyph: .system(size: 15 * scale)
        case .headTitle: .system(size: 15 * scale, weight: .semibold)
        case .tableHeader: .system(size: 12 * scale, weight: .medium)
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
        /// The space above and below a standard row's words beyond the row's own padding, which a line that wraps keeps by
        /// growing the row: a row of one line is then exactly its height.
        static let rowTextPadding: CGFloat = 6
        /// A card's side margin, where a row's text starts when it has no lead.
        static let inset: CGFloat = 16
        /// The lead column, in which a tile, a symbol or a mark sits; text starts after it, at 52.
        static let leadColumn: CGFloat = 24
        static let textInset: CGFloat = 52
        static let controlWidth: CGFloat = 200
        /// A field's height, which the system draws and a read-only value is as tall as.
        static let controlHeight: CGFloat = 26
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
        static let pageTableRow: CGFloat = 30
        /// The space above and below a table row's cells, which a cell that wraps keeps by growing the row.
        static let tableCellPadding: CGFloat = 7
        static let cardRadius: CGFloat = 10
        static let controlRadius: CGFloat = 7
        static let tile: CGFloat = 24
        /// A tile's corner radius and the box its symbol is fitted in, as shares of its side: the symbol keeps even
        /// padding whatever its shape, as in System Settings' sidebar.
        static let tileRounding: CGFloat = 0.27
        static let tileGlyph: CGFloat = 0.62
        static let headTile: CGFloat = 44
        /// A small search field at a list's trailing edge, and the button beside it that changes what it searches by.
        static let searchWidth: CGFloat = 200
        static let searchSpacing: CGFloat = 8
        /// The width of every pop-up: enough for the longest choice in common use, such as Where I Left Off.
        static let popUpWidth: CGFloat = 168
        /// The sidebar's tile.
        static let sidebarTile: CGFloat = 20
        /// A color swatch and the dot that marks the chosen one, and the space between swatches.
        static let swatch: CGFloat = 18
        static let swatchDot: CGFloat = 6
        static let swatchSpacing: CGFloat = 8
        /// How much of the system's color well shows over a swatch that stands for it: none to the eye, all to the pointer.
        static let invisibleWell: Double = 0.02
        /// A choice tile's picture is wider than tall, as the board draws it: 186 by 104 in the column.
        static let choiceAspect: CGFloat = 186 / 104
        /// A theme tile's sidebar, as a share of its width, and its bars and lines: height, spacing, how many bars the
        /// sidebar has, the page's side and top padding, the sidebar's side padding, and the heading line's share of the width.
        static let previewSidebar: CGFloat = 0.3
        static let previewLine: CGFloat = 5
        static let previewLineSpacing: CGFloat = 7
        static let previewSidebarLines = 5
        static let previewPadding: CGFloat = 14
        static let previewTop: CGFloat = 22
        static let previewSidebarPadding: CGFloat = 10
        static let previewHeading: CGFloat = 0.55
        /// The space above and below the rows a preview card draws.
        static let previewCardInset: CGFloat = 4
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
        /// A table's column widths, by what they hold, and its action and check columns.
        enum Column {
            static let state: CGFloat = 70
            static let day: CGFloat = 90
            static let label: CGFloat = 110
            static let address: CGFloat = 130
            static let time: CGFloat = 150
            static let who: CGFloat = 200
            static let setting: CGFloat = 255
            static let action: CGFloat = 88
            static let check: CGFloat = 18
        }
        /// The space between a page's sections, and above and below its column.
        static let pageSpacing: CGFloat = 32
        /// The space between a card and the row of buttons under it, which sit nearer than a section does.
        static let barGap: CGFloat = 14
        /// Below the toolbar: a head card sits 62 points under the window's top, as the boards draw.
        static let pageTop: CGFloat = 10
        /// More room above the first section of a page when it opens with its name (the boards put the card 92.5 points under the
        /// window's top), and above one that opens with its name and a line under it (105.5): a head card needs none.
        static let firstHeaderInset: CGFloat = 5.5
        static let firstHeaderWithLineInset: CGFloat = 2
        static let pageBottom: CGFloat = 58
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
        static let sheetRadius: CGFloat = 14
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
