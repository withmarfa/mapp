import SwiftUI

/// The symbol next to a disk path, wherever its text appears in a row. Settings draws no symbol before an address.
enum SettingsTextGlyph: String {
    case folder

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
