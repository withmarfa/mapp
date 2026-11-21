import AppKit
import SwiftUI

/// Where Settings > Appearance keeps what it chooses for the whole app.
nonisolated enum AppearanceKey {
    static let theme = "theme"
    static let accent = "accentColor"
    static let highlights = "highlightColor"
    static let textFont = "textFont"
    static let codeFont = "codeFont"
    static let all = [theme, accent, highlights, textFont, codeFont]
}

/// Whether the app follows the Mac's light or dark appearance, or keeps one of its own.
nonisolated enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    static let standard = AppTheme.system

    var id: Self { self }

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    static func stored(in defaults: UserDefaults = .standard) -> AppTheme {
        defaults.string(forKey: AppearanceKey.theme).flatMap(Self.init(rawValue:)) ?? standard
    }

    /// Sets the app's appearance. A Debug launch that fixes one for a screenshot (`-MAPPAppearance`) keeps it.
    @MainActor static func apply(_ theme: AppTheme) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-MAPPAppearance") { return }
        #endif
        guard NSApp.appearance?.name != theme.appearance?.name else { return }
        NSApp.appearance = theme.appearance
    }
}

/// The color MAPP is tinted with: the system's accent, one MAPP offers, or a color of the person's own, kept as its hex.
/// A stored value that is none of these is the system's accent.
nonisolated enum AccentChoice: Hashable, RawRepresentable {
    case system
    case offered(Offered)
    /// A color the person made, as `#RRGGBB`.
    case custom(String)

    enum Offered: String, CaseIterable, Identifiable {
        case purple, pink, red, orange, yellow, green, graphite

        var id: Self { self }

        var nsColor: NSColor {
            switch self {
            case .purple: .systemPurple
            case .pink: .systemPink
            case .red: .systemRed
            case .orange: .systemOrange
            case .yellow: .systemYellow
            case .green: .systemGreen
            case .graphite: .systemGray
            }
        }
    }

    static let standard = AccentChoice.system

    init?(rawValue: String) {
        if rawValue == "system" {
            self = .system
        } else if let offered = Offered(rawValue: rawValue) {
            self = .offered(offered)
        } else if Self.rgb(fromHex: rawValue) != nil {
            self = .custom(rawValue.uppercased())
        } else {
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .system: "system"
        case .offered(let offered): offered.rawValue
        case .custom(let hex): hex
        }
    }

    static func stored(in defaults: UserDefaults = .standard) -> AccentChoice {
        defaults.string(forKey: AppearanceKey.accent).flatMap(Self.init(rawValue:)) ?? standard
    }

    /// The color the app is tinted with, or nil where the system's accent stands.
    var nsColor: NSColor? {
        switch self {
        case .system: nil
        case .offered(let offered): offered.nsColor
        case .custom(let hex): Self.rgb(fromHex: hex).map { NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1) }
        }
    }

    var color: Color? { nsColor.map(Color.init(nsColor:)) }

    /// A color of the person's own, kept as its hex.
    static func custom(_ color: Color) -> AccentChoice {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .controlAccentColor
        return .custom(hex(of: resolved))
    }

    static func hex(of color: NSColor) -> String {
        let color = color.usingColorSpace(.sRGB) ?? color
        return String(
            format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded()))
    }

    static func rgb(fromHex text: String) -> (red: Double, green: Double, blue: Double)? {
        guard text.count == 7, text.hasPrefix("#"), let value = Int(text.dropFirst(), radix: 16) else { return nil }
        return (Double(value >> 16 & 0xFF) / 255, Double(value >> 8 & 0xFF) / 255, Double(value & 0xFF) / 255)
    }
}

extension View {
    /// Tints the view with the accent the person chose, or leaves the system's.
    func appAccent() -> some View { modifier(AppAccentTint()) }
}

private struct AppAccentTint: ViewModifier {
    @AppStorage(AppearanceKey.accent) private var accent = AccentChoice.standard

    func body(content: Content) -> some View {
        content.tint(accent.color)
    }
}

/// The color behind highlighted text on an item's page.
nonisolated enum HighlightChoice: String, CaseIterable, Identifiable {
    case yellow, orange, green, blue, pink, purple, accent

    static let standard = HighlightChoice.yellow

    var id: Self { self }

    static func stored(in defaults: UserDefaults = .standard) -> HighlightChoice {
        defaults.string(forKey: AppearanceKey.highlights).flatMap(Self.init(rawValue:)) ?? standard
    }

    /// The soft color the page paints, as CSS. The standard yellow is the page's own, so it gives nil.
    func css(accent: NSColor) -> String? {
        let base: NSColor
        switch self {
        case .yellow: return nil
        case .orange: base = .systemOrange
        case .green: base = .systemGreen
        case .blue: base = .systemBlue
        case .pink: base = .systemPink
        case .purple: base = .systemPurple
        case .accent: base = accent
        }
        let color = base.usingColorSpace(.sRGB) ?? base
        return String(
            format: "rgba(%d, %d, %d, 0.38)", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded()))
    }
}

/// The fonts of an item's text and its code. The interface stays the system font.
nonisolated enum FontChoice {
    /// The font families installed on this Mac, by name.
    static func installedFamilies() -> [String] {
        NSFontManager.shared.availableFontFamilies.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The installed families that are monospaced.
    static func installedMonospacedFamilies() -> [String] {
        installedFamilies().filter { family in
            guard let member = NSFontManager.shared.availableMembers(ofFontFamily: family)?.first,
                  let name = member.first as? String, let font = NSFont(name: name, size: 12)
            else { return false }
            return font.isFixedPitch
        }
    }

    /// The stored family where it is installed, or nil where it is not chosen or has since been uninstalled, which the
    /// page and the editor read as the default.
    static func resolved(_ stored: String, among installed: [String]) -> String? {
        stored.isEmpty || !installed.contains(stored) ? nil : stored
    }

    /// A family as a CSS font list, quoted, with the generic family the page falls back to.
    static func css(family: String, generic: String) -> String {
        let quoted = family.replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: "\"", with: "")
        return "\"\(quoted)\", \(generic)"
    }
}
