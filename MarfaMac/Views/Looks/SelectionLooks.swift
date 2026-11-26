import AppKit
import SwiftUI

/// The gray that marks a chosen row and a row under the pointer in a value panel, a filter panel and a calendar, as
/// `SoftSelection` does in a list. Black over light and white over dark, at the same strength (`docs/look.md`).
nonisolated enum SelectionLooks {
    static let chosenOpacity = 0.08
    static let hoverOpacity = 0.047
    /// A chosen card's ring, which has no fill to show it, so it is stronger than a row's wash: on the dark ground the same
    /// 8% white is lost against the card's own edge.
    static let cardRingLightOpacity = 0.13
    static let cardRingDarkOpacity = 0.26

    static func chosen(for scheme: ColorScheme) -> Color { wash(chosenOpacity, for: scheme) }
    static func hover(for scheme: ColorScheme) -> Color { wash(hoverOpacity, for: scheme) }
    static func cardRing(for scheme: ColorScheme) -> Color {
        wash(scheme == .dark ? cardRingDarkOpacity : cardRingLightOpacity, for: scheme)
    }

    /// The same wash as an `NSColor` for a layer, drawn in `appearance`. The system's label color is left out because
    /// its own alpha is not the strength the tokens name.
    static func layerColor(_ opacity: Double, in appearance: NSAppearance) -> CGColor {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return (isDark ? NSColor.white : NSColor.black).withAlphaComponent(opacity).cgColor
    }

    private static func wash(_ opacity: Double, for scheme: ColorScheme) -> Color {
        (scheme == .dark ? Color.white : Color.black).opacity(opacity)
    }
}
