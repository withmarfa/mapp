import SwiftUI

/// The color a type's mark and chip take, chosen by the type's icon id (`ItemType.icon`, an Iconify id such as
/// `lucide:book-open`). The key is only the icon, so no item type is named here. The table follows the design's
/// `typeTones`, which is keyed by SF Symbol; each Lucide id takes the tone of the symbol that means the same.
nonisolated enum TypeTone: String, CaseIterable, Sendable {
    case blue, green, orange, red, purple, teal, yellow, pink, indigo, gray

    /// Any icon not in the table, including no icon at all.
    static let neutral = TypeTone.gray

    /// A tone with no counterpart in the design's table is marked "guess" and is a choice to confirm.
    static let table: [String: TypeTone] = [
        "lucide:sticky-note": .yellow,
        "lucide:highlighter": .yellow,
        "lucide:square-check-big": .blue,
        "lucide:message-square": .blue,  // guess: the design's envelope
        "lucide:calendar": .red,
        "lucide:terminal": .indigo,
        "lucide:scroll-text": .gray,
        "lucide:signpost": .orange,
        "lucide:briefcase": .blue,
        "lucide:book-open": .orange,
        "lucide:library-big": .orange,  // guess: a shelf of the design's closed book
        "lucide:bookmark": .teal,
        "lucide:newspaper": .teal,
        "lucide:globe": .teal,
        "lucide:user": .purple,
        "lucide:file-image": .green,
        "lucide:map-pin": .green,  // guess: no place in the design
        "lucide:file": .gray,
        "lucide:shapes": .gray,  // guess: the generic base
        "lucide:layers": .indigo,  // guess: the design's list.bullet.rectangle
        "lucide:gamepad-2": .indigo,  // guess: no game in the design
        "lucide:film": .pink,
        "lucide:file-video-camera": .pink,
        "lucide:tv": .pink,
        "lucide:circle-play": .pink,
        "lucide:file-music": .pink,
        "lucide:audio-lines": .pink,
        "lucide:disc-3": .pink,
    ]

    /// The tone's name, which Settings > Layouts says a type's color is.
    var title: String {
        switch self {
        case .blue: String(localized: "Blue")
        case .green: String(localized: "Green")
        case .orange: String(localized: "Orange")
        case .red: String(localized: "Red")
        case .purple: String(localized: "Purple")
        case .teal: String(localized: "Teal")
        case .yellow: String(localized: "Yellow")
        case .pink: String(localized: "Pink")
        case .indigo: String(localized: "Indigo")
        case .gray: String(localized: "Gray")
        }
    }

    init(icon id: String?) {
        self = id.flatMap { Self.table[$0] } ?? Self.neutral
    }

    /// The tone's color in the design's light and dark values (`--tile-*` in the design's CSS).
    func color(for scheme: ColorScheme) -> Color {
        let (r, g, b) = components(dark: scheme == .dark)
        return Color(.sRGB, red: r, green: g, blue: b)
    }

    /// The pale square behind a mark, or a type chip's fill: the tone at `opacity`.
    func fill(_ opacity: Double, for scheme: ColorScheme) -> Color {
        color(for: scheme).opacity(opacity)
    }

    /// The name on a tint of the tone (the tinted chip and a person's circle), a step apart from it so the words read:
    /// `depth` (the chip's `tintedInkDepth` unless given) of the way to black in light, and `nameLiftDark` of the way to white in dark.
    func nameInk(_ looks: ChipLooks, depth: Double? = nil, for scheme: ColorScheme) -> Color {
        let (r, g, b) = nameInkComponents(looks, depth: depth, dark: scheme == .dark)
        return Color(.sRGB, red: r, green: g, blue: b)
    }

    func nameInkComponents(_ looks: ChipLooks, depth: Double? = nil, dark: Bool) -> (Double, Double, Double) {
        let (r, g, b) = components(dark: dark)
        guard dark else {
            let keep = 1 - (depth ?? looks.tintedInkDepth)
            return (r * keep, g * keep, b * keep)
        }
        let lift = looks.nameInkLiftDark
        return (r + (1 - r) * lift, g + (1 - g) * lift, b + (1 - b) * lift)
    }

    /// The tone as the page's `--tone-<name>` custom property: a mark's color, which is the tone itself.
    func cssColor(dark: Bool) -> String { Self.cssRGB(of: components(dark: dark)) }

    /// The tone as a CSS `rgb()` at `alpha`, and a color of the page's own as the same function.
    func cssRGBA(_ alpha: Double, dark: Bool) -> String {
        let (r, g, b) = components(dark: dark)
        return "rgba(\(Self.byte(r)), \(Self.byte(g)), \(Self.byte(b)), \(String(format: "%g", alpha)))"
    }

    static func cssRGB(of color: (Double, Double, Double)) -> String {
        "rgb(\(Self.byte(color.0)), \(Self.byte(color.1)), \(Self.byte(color.2)))"
    }

    private static func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }

    func components(dark: Bool) -> (Double, Double, Double) {
        let hex = dark ? darkHex : lightHex
        return (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    private var lightHex: Int {
        switch self {
        case .blue: 0x007AFF
        case .green: 0x28A745
        case .orange: 0xF08A00
        case .red: 0xEB4137
        case .purple: 0xA650D8
        case .teal: 0x17A2B8
        case .yellow: 0xE0A800
        case .pink: 0xE8437A
        case .indigo: 0x5856D6
        case .gray: 0x8A8A90
        }
    }

    private var darkHex: Int {
        switch self {
        case .blue: 0x2B95FF
        case .green: 0x34C759
        case .orange: 0xFF9F0A
        case .red: 0xFF5A50
        case .purple: 0xBF5AF2
        case .teal: 0x40C8E0
        case .yellow: 0xFFD426
        case .pink: 0xFF5C8A
        case .indigo: 0x7D7AFF
        case .gray: 0x98989D
        }
    }
}
