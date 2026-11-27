import SwiftUI

/// The symbol next to a path or address, wherever its text appears in a row.
enum SettingsTextGlyph: String {
    case folder
    case link

    var icon: some View {
        Image(systemName: rawValue)
            .settingsFont(.pathGlyph)
            .foregroundStyle(SettingsTokens.secondaryText)
            .accessibilityHidden(true)
    }
}

extension Text {
    @ViewBuilder func withSettingsGlyph(_ glyph: SettingsTextGlyph?) -> some View {
        if let glyph {
            HStack(alignment: .firstTextBaseline, spacing: SettingsTokens.Metric.pathGlyphGap) {
                glyph.icon
                self
            }
        } else {
            self
        }
    }
}
