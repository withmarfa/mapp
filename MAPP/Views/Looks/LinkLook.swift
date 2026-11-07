import Foundation

/// How a link to another item reads in a note's text, as the person chose in Settings. Every look, with its sizes and
/// colors, is here and nowhere else; the page holds none of them. A link to a note that is missing keeps its dashed
/// line in every look.
nonisolated enum LinkLook: String, CaseIterable, Identifiable, Sendable {
    /// The linked item's type icon in the type's color, then the title, underlined under the pointer.
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
    }

    /// The neutral fill of a pill, as black over light and white over dark.
    private enum Neutral {
        static let fillLight = "rgba(0, 0, 0, 0.07)"
        static let fillDark = "rgba(255, 255, 255, 0.11)"
        static let lineLight = "rgba(0, 0, 0, 0.32)"
        static let lineDark = "rgba(255, 255, 255, 0.38)"
    }

    private static func appearance(_ light: String, _ dark: String) -> String { "light-dark(\(light), \(dark))" }

    /// The look as the page's custom properties: Inkkit's wiki link tokens, and for each tone the colors a link to
    /// a note of a type with that tone takes (`--link-icon-<tone>`, `--link-tint-<tone>`), resolved for light and for
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
            all[prefix + "underline"] = self == .mark ? "none" : "underline"
            all[prefix + "underline-thickness"] = Measure.underlineThickness
            all[prefix + "underline-offset"] = self == .quiet ? Measure.quietUnderlineOffset : Measure.underlineOffset
            if self == .quiet {
                all[prefix + "underline-color"] = Self.appearance(Neutral.lineLight, Neutral.lineDark)
            }
        }
        return all
    }
}
