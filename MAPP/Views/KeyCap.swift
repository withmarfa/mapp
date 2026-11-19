import SwiftUI

/// A key of a shortcut, drawn as MAPP draws key caps outside menus: one glyph in its own small outlined cap, with no
/// fill, the glyph a touch lighter than secondary text. `onAccent` is for a cap inside a primary button.
struct KeyCap: View {
    let key: String
    var onAccent = false

    var body: some View {
        Text(key)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(onAccent ? Color.white.opacity(0.75) : Color.primary.opacity(0.42))
            .padding(.horizontal, 3)
            .frame(minWidth: 16)
            .frame(height: 16)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(onAccent ? Color.white.opacity(0.45) : Color.primary.opacity(0.2), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

/// A shortcut such as ⇧⌘P as one cap for each glyph. Menus keep the system's glyphs; this is for where MAPP draws a
/// shortcut itself.
struct ShortcutKeys: View {
    let shortcut: String
    var onAccent = false

    init(_ shortcut: String, onAccent: Bool = false) {
        self.shortcut = shortcut
        self.onAccent = onAccent
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(shortcut.enumerated()), id: \.offset) { _, glyph in
                KeyCap(key: String(glyph), onAccent: onAccent)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut)
    }
}
