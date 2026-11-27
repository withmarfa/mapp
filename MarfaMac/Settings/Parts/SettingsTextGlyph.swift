import SwiftUI

/// The symbol next to a path or address, wherever its text appears in a row.
enum SettingsTextGlyph: String {
    case folder
    case link
}

extension Text {
    @ViewBuilder func withSettingsGlyph(_ glyph: SettingsTextGlyph?) -> some View {
        if let glyph {
            HStack(alignment: .firstTextBaseline, spacing: SettingsTokens.Metric.pathGlyphGap) {
                Image(systemName: glyph.rawValue)
                    .settingsFont(.pathGlyph)
                    .foregroundStyle(SettingsTokens.secondaryText)
                    .accessibilityHidden(true)
                self
            }
        } else {
            self
        }
    }
}
