import SwiftUI

/// A status's symbol, drawn the same wherever the app shows one: the page, the right sidebar, a table, a gallery card,
/// a value panel and a list row. `size` is the symbol's font size.
struct StatusMark: View {
    let symbol: StatusSymbol
    let size: CGFloat
    /// Drawn in white, on a row the selection colors with the accent, where a blue or grey symbol would vanish.
    var onAccent = false

    init(_ symbol: StatusSymbol, size: CGFloat, onAccent: Bool = false) {
        self.symbol = symbol
        self.size = size
        self.onAccent = onAccent
    }

    init(group: StatusGroup?, size: CGFloat, onAccent: Bool = false) {
        self.init(StatusSymbol(group: group), size: size, onAccent: onAccent)
    }

    var body: some View {
        Image(systemName: symbol.systemName)
            .font(.system(size: size))
            .foregroundStyle(onAccent ? AnyShapeStyle(.white) : symbol.tint.style)
            .accessibilityHidden(true)
    }
}

extension StatusSymbol.Tint {
    var style: AnyShapeStyle {
        switch self {
        case .blue: AnyShapeStyle(Color.blue)
        case .secondary: AnyShapeStyle(.secondary)
        case .tertiary: AnyShapeStyle(.tertiary)
        }
    }
}
