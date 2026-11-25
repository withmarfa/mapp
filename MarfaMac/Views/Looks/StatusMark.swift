import SwiftUI

/// A status's symbol, drawn the same wherever the app shows one: the page, the right sidebar, a table, a gallery card,
/// a value panel and a list row. `size` is the symbol's font size.
struct StatusMark: View {
    let symbol: StatusSymbol
    let size: CGFloat

    init(_ symbol: StatusSymbol, size: CGFloat) {
        self.symbol = symbol
        self.size = size
    }

    init(group: StatusGroup?, size: CGFloat) {
        self.init(StatusSymbol(group: group), size: size)
    }

    var body: some View {
        Image(systemName: symbol.systemName)
            .font(.system(size: size))
            .foregroundStyle(symbol.tint.style)
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
