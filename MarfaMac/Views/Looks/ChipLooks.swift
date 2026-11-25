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
    /// A chip's text: 12 points at medium weight on the page, and in a row `rowTextSize` at regular weight.
    let textSize = 12.0
    /// Space at each side of a chip's content, between its parts, and the extra start space of each kind.
    var padding = 8.0
    var gap = 5.0
    var typePaddingStart = 6.0
    var tagPaddingStart = 7.0
    var filterPaddingEnd = 6.0
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
    /// How far the tinted chip's name sits toward black in light. In dark it takes the tone's own ink.
    var tintedInkDepth = 0.46
    /// A person's circle: the purple tone's opacity over the window, in light and in dark, and how far the letters sit
    /// toward black in light.
    var personFillOpacity = 0.15
    var personFillOpacityDark = 0.26
    var personInkDepth = 0.28
    /// The pale square behind a type mark, as the tone's opacity.
    var markOpacity = 0.17
    /// How far a type's icon and name sit from the tone of their tint in light, toward black.
    var inkDepth = 0.22
    /// The same in dark, toward white (then held under `inkCeilingDark`).
    var inkDepthDark = 0.08
    /// The brightest a type's icon and name may be in dark, as a relative luminance, so that the bright tones (yellow,
    /// orange, teal, green) sit level with the others and no chip stands out.
    var inkCeilingDark = 0.36
    /// The type mark beside a name that is shown as a fact, and a status symbol's font size at the page size.
    var chipMarkSize = 14.0
    var statusSymbolSize = 14.0
    /// The one wash of an option, a status and a tag chip, as black over light and white over dark at the same strength.
    var chipWashOpacity = 0.035
    /// A filter chip's fill: the search field in grey.
    var filterFillOpacityLight = 0.07
    var filterFillOpacityDark = 0.11
    /// The chevron on a chip that opens a menu.
    var chevronOpacity = 0.5

    static let defaults = ChipLooks()

    /// A chip's text: medium weight on the page, regular in a row, at the interface's text size over the design's 13.
    func chipFont(for size: ChipSize, textSize interfaceSize: CGFloat) -> Font {
        .system(size: textSize(for: size) * interfaceSize / 13, weight: size == .page ? .medium : .regular)
    }

    func height(for size: ChipSize) -> Double { size == .page ? height : rowHeight }
    func textSize(for size: ChipSize) -> Double { size == .page ? textSize : rowTextSize }
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

    /// A person's circle is the purple tone, pale: its fill is the tone at `personFillOpacity`, and its letters are the
    /// tone toward black in light and the tone's dark ink in dark.
    func personFill(dark: Bool) -> Double { dark ? personFillOpacityDark : personFillOpacity }

    func personInk(dark: Bool) -> (Double, Double, Double) {
        let (r, g, b) = TypeTone.purple.components(dark: dark)
        guard !dark else { return TypeTone.purple.inkComponents(self, dark: true) }
        return (r * (1 - personInkDepth), g * (1 - personInkDepth), b * (1 - personInkDepth))
    }

    func personFillColor(for scheme: ColorScheme) -> Color {
        TypeTone.purple.fill(personFill(dark: scheme == .dark), for: scheme)
    }

    func personInkColor(for scheme: ColorScheme) -> Color {
        let (r, g, b) = personInk(dark: scheme == .dark)
        return Color(.sRGB, red: r, green: g, blue: b)
    }

    func filterFill(for scheme: ColorScheme) -> Color {
        neutral(scheme == .dark ? filterFillOpacityDark : filterFillOpacityLight, for: scheme)
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
            "--chip-padding": px(looks.padding),
            "--chip-gap": px(looks.gap),
            "--chip-type-padding-start": px(looks.typePaddingStart),
            "--chip-tag-padding-start": px(looks.tagPaddingStart),
            "--chip-filter-padding-end": px(looks.filterPaddingEnd),
            "--chip-person-circle": px(looks.personCircle),
            "--chip-person-initials-size": px(looks.personInitialsSize),
            "--chip-person-gap": px(looks.personGap),
            "--chip-mark-opacity": alpha(looks.markOpacity),
            "--chip-mark-size": px(looks.chipMarkSize),
            "--chip-wash": neutral(looks.chipWashOpacity),
            "--chip-person-fill": TypeTone.purple.cssRGBA(looks.personFill(dark: dark), dark: dark),
            "--chip-person-ink": TypeTone.cssRGB(of: looks.personInk(dark: dark)),
            "--chip-filter-fill": neutral(dark ? looks.filterFillOpacityDark : looks.filterFillOpacityLight),
            "--chip-chevron-opacity": alpha(looks.chevronOpacity),
        ]
    }
}
