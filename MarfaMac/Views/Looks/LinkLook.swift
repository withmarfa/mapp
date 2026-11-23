import Foundation

/// How a link to another item reads in an item's text, as the person chose in Settings. Every look, with its sizes and
/// colors, is here and nowhere else; the page holds none of them. A link to an item that is missing keeps its dashed
/// line in every look, and in the mark look a lighter dotted one. Every look shows that a link opens on a Command-click
/// the same way (`openCue`), since a plain click places the caret.
nonisolated enum LinkLook: String, CaseIterable, Identifiable, Sendable {
    /// The linked item's type icon in the type's color, then the title, with a dotted underline.
    case mark
    /// The title underlined, with no icon.
    case underline
    /// A chip in the type's tint, with the icon.
    case tintedPill
    /// A neutral chip in the line, with the icon.
    case pill
    /// Body text with a fine underline and no icon.
    case quiet
    /// The accent color, as the editor draws a link when nothing else is chosen.
    case text

    static let key = "linkLook"
    static let standard = LinkLook.mark

    static func stored(in defaults: UserDefaults = .standard) -> LinkLook {
        defaults.string(forKey: key).flatMap(Self.init(rawValue:)) ?? standard
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .mark: String(localized: "Mark")
        case .underline: String(localized: "Underline")
        case .tintedPill: String(localized: "Tinted Pill")
        case .pill: String(localized: "Pill")
        case .quiet: String(localized: "Quiet")
        case .text: String(localized: "Text")
        }
    }

    /// Whether the type icon is drawn.
    var showsIcon: Bool {
        switch self {
        case .mark, .tintedPill, .pill: true
        case .underline, .quiet, .text: false
        }
    }

    /// Whether the icon takes the type's color; otherwise it takes the text's.
    private var colorsIcon: Bool { self == .mark || self == .tintedPill }

    private var isPill: Bool { self == .tintedPill || self == .pill }

    /// The look's measures, in ems of the text it sits in so a link in a heading or at another text size keeps its
    /// proportions.
    private enum Measure {
        static let pillPaddingInline = "0.4em"
        static let pillPaddingBlock = "0.08em"
        static let pillRadius = "0.4em"
        static let underlineThickness = "1px"
        static let underlineOffset = "2px"
        static let quietUnderlineOffset = "3px"
        static let iconSize = "0.95em"
        static let iconGap = "0.3em"
        /// The mark look's dots, as a share of the text's own color so they read on light and dark; a missing link's
        /// are lighter.
        static let markDots = "color-mix(in srgb, currentcolor 55%, transparent)"
        static let markMissingDots = "color-mix(in srgb, currentcolor 28%, transparent)"
        /// The fill behind a link under the pointer, and the stronger one while Command is held and a click would open
        /// it, as a share of the text's own color. It lies over a pill's own fill.
        static let hoverFill = "color-mix(in srgb, currentcolor 8%, transparent)"
        static let openFill = "color-mix(in srgb, currentcolor 16%, transparent)"
        static let webLinkRadius = "0.2em"
    }

    /// The neutral fill of a pill, as black over light and white over dark.
    private enum Neutral {
        static let fillLight = "rgba(0, 0, 0, 0.07)"
        static let fillDark = "rgba(255, 255, 255, 0.11)"
        static let lineLight = "rgba(0, 0, 0, 0.32)"
        static let lineDark = "rgba(255, 255, 255, 0.38)"
    }

    private static func appearance(_ light: String, _ dark: String) -> String { "light-dark(\(light), \(dark))" }

    /// What every look shows of a link under the pointer: a fill, and a stronger one while Command is held. Inkkit adds
    /// the hand pointer, the underline and its hint for a link a Command-click opens, so the cue is the same in every
    /// look and never says a plain click opens.
    private static var openCue: [String: String] {
        [
            "--inkkit-link-hover-background": Measure.hoverFill,
            "--inkkit-link-open-background": Measure.openFill,
            "--inkkit-link-radius": Measure.webLinkRadius,
        ]
    }

    /// The look as the page's custom properties: Inkkit's link and wiki link tokens, and for each tone the colors a link to
    /// an item of a type with that tone takes (`--link-icon-<tone>`, `--link-tint-<tone>`), resolved for light and for
    /// dark at once by `light-dark()` so an appearance change needs no resend. The tint is the tone's chip color
    /// (`TypeTone.cssColors`), the same fill a chip in the item's header has.
    @MainActor
    func cssVariables(looks: ChipLooks = .current) -> [String: String] {
        var all: [String: String] = [:]
        for tone in TypeTone.allCases {
            let light = TypeTone.cssColors(for: tone, dark: false, looks: looks)
            let dark = TypeTone.cssColors(for: tone, dark: true, looks: looks)
            all["--link-tint-\(tone.rawValue)"] = Self.appearance(light["--tone-chip"]!, dark["--tone-chip"]!)
            all["--link-icon-\(tone.rawValue)"] =
                colorsIcon ? Self.appearance(light["--tone-ink"]!, dark["--tone-ink"]!) : "currentcolor"
        }
        all.merge(Self.openCue) { _, new in new }
        let prefix = "--inkkit-wiki-link-"
        if self == .text {
            all[prefix + "icon-display"] = "none"
            return all
        }
        // The text of a link in any look but Text is the text around it.
        all[prefix + "color"] = "currentcolor"
        all[prefix + "hover-color"] = "currentcolor"
        if !showsIcon { all[prefix + "icon-display"] = "none" }
        all[prefix + "icon-size"] = Measure.iconSize
        all[prefix + "icon-gap"] = Measure.iconGap
        if isPill {
            all[prefix + "underline"] = "none"
            all[prefix + "hover-underline"] = "none"
            all[prefix + "padding-inline"] = Measure.pillPaddingInline
            all[prefix + "padding-block"] = Measure.pillPaddingBlock
            all[prefix + "radius"] = Measure.pillRadius
            // A link with no known type has no tint, and its fill is then this neutral one, so it never reads as bare text.
            all[prefix + "background"] = Self.appearance(Neutral.fillLight, Neutral.fillDark)
            // The tint is already the tone's chip fill, so a tinted pill takes it whole.
            if self == .tintedPill { all[prefix + "tint-strength"] = "100%" }
        } else {
            all[prefix + "underline"] = "underline"
            all[prefix + "underline-thickness"] = Measure.underlineThickness
            all[prefix + "underline-offset"] = self == .quiet ? Measure.quietUnderlineOffset : Measure.underlineOffset
            if self == .mark {
                all[prefix + "underline-style"] = "dotted"
                all[prefix + "underline-color"] = Measure.markDots
                all[prefix + "missing-underline-style"] = "dotted"
                all[prefix + "missing-underline-color"] = Measure.markMissingDots
            }
            if self == .quiet {
                all[prefix + "underline-color"] = Self.appearance(Neutral.lineLight, Neutral.lineDark)
            }
        }
        return all
    }
}
