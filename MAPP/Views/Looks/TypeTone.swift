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

    /// The tone as CSS custom properties for the web page: `--tone`, and `--tone-mark` and `--tone-chip` for the pale
    /// fills at the opacities in force.
    @MainActor static func cssColors(for icon: String?, dark: Bool, looks: ChipLooks = .current) -> [String: String] {
        cssColors(for: TypeTone(icon: icon), dark: dark, looks: looks)
    }

    /// The same for a tone chosen directly, such as an option's (`OptionTone`).
    @MainActor static func cssColors(for tone: TypeTone, dark: Bool, looks: ChipLooks = .current) -> [String: String] {
        let (r, g, b) = tone.components(dark: dark)
        let (red, green, blue) = (Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
        return [
            "--tone": "rgb(\(red), \(green), \(blue))",
            "--tone-mark": "rgba(\(red), \(green), \(blue), \(String(format: "%g", looks.markOpacity)))",
            "--tone-chip": "rgba(\(red), \(green), \(blue), \(String(format: "%g", looks.typeTintOpacity)))",
        ]
    }

    private func components(dark: Bool) -> (Double, Double, Double) {
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
