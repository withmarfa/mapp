import SwiftUI

/// The two sizes a chip is drawn at: on the page and in the right sidebar, and, a little smaller, in a list row.
enum ChipSize: Hashable, Sendable {
    case page, row
}

/// Every chip look, size and type color, as a named value with a default, in this one place. `current` is what is in
/// force: the defaults, and in a Debug build the values of the tuning panel's `Chips` knobs. Values come from the
/// design's "Round nine" CSS (`[data-chips="set"]`).
struct ChipLooks: Equatable, Sendable {
    /// Every chip is this tall, so chips side by side always line up.
    var height = 22.0
    var cornerRadius = 6.0
    /// The page's own text size at 13 points, so a value reads at one size whatever its kind.
    var textSize = 13.0
    /// Space at each side of a chip's content, between its parts, and the extra start space of each kind.
    var padding = 8.0
    var gap = 5.0
    var typePaddingStart = 6.0
    var tagPaddingStart = 7.0
    var filterPaddingEnd = 6.0
    /// A person's initials circle, and its text and the gap to the name.
    var personCircle = 17.0
    var personInitialsSize = 8.0
    var personGap = 6.0
    /// A status chip's symbol, as a font size, at the page size.
    var statusSymbolSize = 14.0
    /// What differs in a list row: the chip's height and text size, and a person's circle and its initials. Every other
    /// measure (padding, gaps, marks) follows the height (`unit(for:)`).
    var rowHeight = 20.0
    var rowTextSize = 11.5
    var rowPersonCircle = 20.0
    var rowPersonInitialsSize = 9.0
    /// A type chip's fill in light, as the tone's opacity.
    var typeTintOpacity = 0.13
    /// The same in dark.
    var typeTintOpacityDark = 0.10
    /// The pale square behind a type mark, as the tone's opacity.
    var markOpacity = 0.17
    /// How far a type's icon and name sit from the tone of their tint in light, toward black.
    var inkDepth = 0.22
    /// The same in dark, toward white (then held under `inkCeilingDark`).
    var inkDepthDark = 0.08
    /// The brightest a type's icon and name may be in dark, as a relative luminance, so that the bright tones (yellow,
    /// orange, teal, green) sit level with the others and no chip stands out.
    var inkCeilingDark = 0.36
    /// The type icon inside a type or link chip, which has no square of its own.
    var chipMarkSize = 13.0
    /// A status chip's edge: its width and its opacity in light and dark.
    var statusEdgeWidth = 0.5
    var edgeOpacityLight = 0.16
    var edgeOpacityDark = 0.18
    /// The neutral fill of an option or a tag chip, and the faint fill a status chip has in dark.
    var optionFillOpacityLight = 0.045
    var optionFillOpacityDark = 0.07
    var tagFillOpacityLight = 0.045
    var tagFillOpacityDark = 0.07
    var statusDarkFillOpacity = 0.07
    /// A filter chip's fill: the search field in grey.
    var filterFillOpacityLight = 0.07
    var filterFillOpacityDark = 0.11
    /// The chevron on a chip that opens a menu.
    var chevronOpacity = 0.5

    static let defaults = ChipLooks()

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

    func optionFill(for scheme: ColorScheme) -> Color {
        neutral(scheme == .dark ? optionFillOpacityDark : optionFillOpacityLight, for: scheme)
    }

    func tagFill(for scheme: ColorScheme) -> Color {
        neutral(scheme == .dark ? tagFillOpacityDark : tagFillOpacityLight, for: scheme)
    }

    func filterFill(for scheme: ColorScheme) -> Color {
        neutral(scheme == .dark ? filterFillOpacityDark : filterFillOpacityLight, for: scheme)
    }

    func edge(for scheme: ColorScheme) -> Color {
        neutral(scheme == .dark ? edgeOpacityDark : edgeOpacityLight, for: scheme)
    }

    /// A status chip is clear in light and faintly filled in dark.
    func statusFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? neutral(statusDarkFillOpacity, for: scheme) : .clear
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
            "--chip-type-tint-opacity": alpha(dark ? looks.typeTintOpacityDark : looks.typeTintOpacity),
            "--chip-mark-opacity": alpha(looks.markOpacity),
            "--chip-mark-size": px(looks.chipMarkSize),
            "--chip-status-edge-width": px(looks.statusEdgeWidth),
            "--chip-edge": neutral(dark ? looks.edgeOpacityDark : looks.edgeOpacityLight),
            "--chip-option-fill": neutral(dark ? looks.optionFillOpacityDark : looks.optionFillOpacityLight),
            "--chip-tag-fill": neutral(dark ? looks.tagFillOpacityDark : looks.tagFillOpacityLight),
            "--chip-status-fill": dark ? neutral(looks.statusDarkFillOpacity) : "transparent",
            "--chip-filter-fill": neutral(dark ? looks.filterFillOpacityDark : looks.filterFillOpacityLight),
            "--chip-chevron-opacity": alpha(looks.chevronOpacity),
        ]
    }
}
