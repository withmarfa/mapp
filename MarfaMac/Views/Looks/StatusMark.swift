import SwiftUI

/// A status's symbol, drawn the same wherever the app shows one: the page, the right sidebar, a table, a gallery card,
/// a value panel and a list row. The size and the tones are this type's own, so no caller picks either.
struct StatusMark: View {
    /// The symbol's font size at the design's 13 point text; its circle is about 14 points across.
    static let size: CGFloat = 15
    /// The in-progress blue as sRGB components in light and in dark, which the page's `--status-blue` holds too.
    static let blue: (light: (Int, Int, Int), dark: (Int, Int, Int)) = ((0, 122, 255), (10, 132, 255))

    let symbol: StatusSymbol
    let scale: CGFloat
    @Environment(\.colorScheme) private var scheme

    init(_ symbol: StatusSymbol, scale: CGFloat = 1) {
        self.symbol = symbol
        self.scale = scale
    }

    init(group: StatusGroup?, scale: CGFloat = 1) {
        self.init(StatusSymbol(group: group), scale: scale)
    }

    var body: some View {
        Image(systemName: symbol.systemName)
            .font(.system(size: Self.size * scale))
            .foregroundStyle(symbol.tint.style(for: scheme))
            .accessibilityHidden(true)
    }
}

extension StatusSymbol.Tint {
    func style(for scheme: ColorScheme) -> AnyShapeStyle {
        switch self {
        case .blue:
            let (r, g, b) = scheme == .dark ? StatusMark.blue.dark : StatusMark.blue.light
            return AnyShapeStyle(Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255))
        case .secondary: return AnyShapeStyle(.secondary)
        case .tertiary: return AnyShapeStyle(.tertiary)
        }
    }
}
