import SwiftUI

/// The gray that marks a chosen row and a row under the pointer in a value panel, a filter panel and a calendar, as
/// `SoftSelection` does in a list. Black over light and white over dark, at the same strength (`docs/look.md`).
nonisolated enum SelectionLooks {
    static let chosenOpacity = 0.08
    static let hoverOpacity = 0.047

    static func chosen(for scheme: ColorScheme) -> Color { wash(chosenOpacity, for: scheme) }
    static func hover(for scheme: ColorScheme) -> Color { wash(hoverOpacity, for: scheme) }

    private static func wash(_ opacity: Double, for scheme: ColorScheme) -> Color {
        (scheme == .dark ? Color.white : Color.black).opacity(opacity)
    }
}
