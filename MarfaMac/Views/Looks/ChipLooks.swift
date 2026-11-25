import SwiftUI

/// The two sizes a chip is drawn at: on the page and in the right sidebar, and, a little smaller, in a list row.
enum ChipSize: Hashable, Sendable {
    case page, row
}

/// Every chip look, size and type color, as a named value with a default, in this one place. `current` is what is in
/// force: the defaults, and in a Debug build the values of the tuning panel's `Chips` knobs. Values come from the
/// design's Foundations boards (F3, F4, F6, F9). The colors are tabled in `docs/look.md`, and a test holds this struct
/// and the page's CSS variables to the same values.
struct ChipLooks: Equatable, Sendable {
    /// Every chip is this tall, so chips side by side always line up.
    let height = 22.0
    var cornerRadius = 7.0
    /// A chip's text: 12 points at `pageWeight` on the page, and in a row `rowTextSize` at `rowWeight`. Weights are the
    /// CSS numbers (400 regular, 500 medium, 600 semibold) so the page and the app read the same value.
    let textSize = 12.0
    let pageWeight = 500
    let rowWeight = 400
    /// A chip's text is the ink at this opacity (in dark, white at the same opacity), a step under a label's.
    var chipTextOpacity = 0.72
    /// A type, a linked item or a person shown as a fact: its name at `factSize` on the page and `rowFactSize` in a row,
    /// at `factWeight`.
    let factSize = 13.0
    let rowFactSize = 12.0
    let factWeight = 400
    let initialsWeight = 600
    /// Space at each side of a chip's content, between its parts, and the extra start space of each kind.
    var padding = 8.0
    var gap = 5.0
    var typePaddingStart = 6.0
    var statusPaddingStart = 6.0
    var tagPaddingStart = 7.0
    /// A person's initials circle, and its text and the gap to the name. The circle is the same in a row.
    var personCircle = 18.0
    var personInitialsSize = 8.5
    var personGap = 6.0
    /// What differs in a list row: the chip's height and text size, and a person's circle and its initials. Every other
    /// measure (padding, gaps, marks) follows the height (`unit(for:)`).
    var rowHeight = 20.0
    var rowTextSize = 11.5
    var rowPersonCircle = 18.0
    var rowPersonInitialsSize = 8.5
    /// The tinted chip's fill in light, as the tone's opacity, and in dark.
    var typeTintOpacity = 0.14
    var typeTintOpacityDark = 0.20
    /// How far the tinted chip's name sits toward black in light, and toward white in dark (`nameInkLiftDark`). Each is
    /// held to a contrast of at least 4.5 to 1 on the fill by `ChipLooksTests`.
    var tintedInkDepth = 0.46
    var nameInkLiftDark = 0.5
    /// A person's circle: the purple tone's opacity over the window, in light and in dark, and how far the letters sit
    /// toward black in light (in dark they take `nameInkLiftDark`).
    var personFillOpacity = 0.15
    var personFillOpacityDark = 0.26
    var personInkDepth = 0.28
    /// The pale square behind a type mark, as the tone's opacity.
    var markOpacity = 0.17
    /// The type mark beside a name that is shown as a fact.
    var chipMarkSize = 14.0
    /// The one wash of an option, a status and a tag chip, as black over light and white over dark at the same strength.
    var chipWashOpacity = 0.035
    /// The app's keyboard focus ring: this opacity of the ink in light and of white in dark, 3 points wide
    /// (`AppFocusRing`). The page's `--focus-ring` holds the same percentage.
    let focusRingOpacity = 0.26
    let focusRingWidth = 3.0
    /// The chevron on a chip that opens a menu.
    var chevronOpacity = 0.5

    static let defaults = ChipLooks()

    /// A chip's text at the interface's text size over the design's 13.
    func chipFont(for size: ChipSize, textSize interfaceSize: CGFloat) -> Font {
        .system(size: textSize(for: size) * interfaceSize / 13, weight: Self.weight(weight(for: size)))
    }

    /// A fact's name (a type, a linked item or a person) at the interface's text size.
    func factFont(for size: ChipSize, textSize interfaceSize: CGFloat) -> Font {
        .system(size: factSize(for: size) * interfaceSize / 13, weight: Self.weight(factWeight))
    }

    static func weight(_ value: Int) -> Font.Weight {
        switch value {
        case ...400: .regular
        case 500: .medium
        default: .semibold
        }
    }

    func height(for size: ChipSize) -> Double { size == .page ? height : rowHeight }
    func textSize(for size: ChipSize) -> Double { size == .page ? textSize : rowTextSize }
    func weight(for size: ChipSize) -> Int { size == .page ? pageWeight : rowWeight }
    func factSize(for size: ChipSize) -> Double { size == .page ? factSize : rowFactSize }
    func personCircle(for size: ChipSize) -> Double { size == .page ? personCircle : rowPersonCircle }
    func personInitialsSize(for size: ChipSize) -> Double { size == .page ? personInitialsSize : rowPersonInitialsSize }

    /// What a measure of the page size is multiplied by at `size`, so a row's chip keeps the page chip's proportions.
    func unit(for size: ChipSize) -> Double { height(for: size) / height }

    #if DEBUG
    static var current: ChipLooks { Tuning.shared.chipLooks }
    #else
    static var current: ChipLooks { defaults }
    #endif

    /// Black over light, white over dark: a neutral fill at `opacity`.
    func neutral(_ opacity: Double, for scheme: ColorScheme) -> Color {
        (scheme == .dark ? Color.white : Color.black).opacity(opacity)
    }

    func chipWash(for scheme: ColorScheme) -> Color {
        neutral(chipWashOpacity, for: scheme)
    }

    /// The text of a chip, and of a fact in a row.
    func chipText(for scheme: ColorScheme) -> Color {
        neutral(chipTextOpacity, for: scheme)
    }

    func focusRing(for scheme: ColorScheme) -> Color {
        neutral(focusRingOpacity, for: scheme)
    }

    /// A person's circle is the purple tone, pale: its fill is the tone at `personFill`, and its letters are the
    /// tone toward black in light and toward white in dark (`TypeTone.nameInkComponents`).
    func personFill(dark: Bool) -> Double { dark ? personFillOpacityDark : personFillOpacity }

    func personInk(dark: Bool) -> (Double, Double, Double) {
        TypeTone.purple.nameInkComponents(self, depth: personInkDepth, dark: dark)
    }

    func personFillColor(for scheme: ColorScheme) -> Color {
        TypeTone.purple.fill(personFill(dark: scheme == .dark), for: scheme)
    }

    func personInkColor(for scheme: ColorScheme) -> Color {
        let (r, g, b) = personInk(dark: scheme == .dark)
        return Color(.sRGB, red: r, green: g, blue: b)
    }

    /// The looks as CSS custom properties for the web page, resolved for light or dark.
    static func cssVariables(dark: Bool, looks: ChipLooks = .current) -> [String: String] {
        func px(_ value: Double) -> String { String(format: "%gpx", value) }
        func alpha(_ opacity: Double) -> String { String(format: "%g", opacity) }
        func neutral(_ opacity: Double) -> String {
            "rgba(\(dark ? "255, 255, 255" : "0, 0, 0"), \(alpha(opacity)))"
        }
        return [
            "--chip-height": px(looks.height),
            "--chip-radius": px(looks.cornerRadius),
            "--chip-text-size": px(looks.textSize),
            "--chip-weight": String(looks.pageWeight),
            "--chip-text-color": neutral(looks.chipTextOpacity),
            "--chip-fact-size": px(looks.factSize),
            "--chip-fact-weight": String(looks.factWeight),
            "--chip-padding": px(looks.padding),
            "--chip-gap": px(looks.gap),
            "--chip-status-padding-start": px(looks.statusPaddingStart),
            "--chip-tag-padding-start": px(looks.tagPaddingStart),
            "--chip-person-circle": px(looks.personCircle),
            "--chip-person-initials-size": px(looks.personInitialsSize),
            "--chip-person-initials-weight": String(looks.initialsWeight),
            "--chip-person-gap": px(looks.personGap),
            "--chip-mark-size": px(looks.chipMarkSize),
            "--chip-wash": neutral(looks.chipWashOpacity),
            "--chip-person-fill": TypeTone.purple.cssRGBA(looks.personFill(dark: dark), dark: dark),
            "--chip-person-ink": TypeTone.cssRGB(of: looks.personInk(dark: dark)),
        ]
    }
}
