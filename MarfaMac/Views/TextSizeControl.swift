import SwiftUI

/// The text size of a page of text in the corner, drawn as an image's size is (`FileZoomControl`): the size as "13 pt"
/// with a chevron, which opens a menu of the sizes with the current one ticked, Make Text Bigger and Make Text Smaller,
/// then Standard Width and Full Width with the page's ticked. Each entry does what the View menu's command does
/// (`TextZoom.page`, and the page width the View menu and Settings set), so there is no sizing rule here. The menu binds
/// no keys, since the View menu's commands are the same ones and own them.
struct TextSizeControl: View {
    /// Whether the size changes what the page shows; where it does not, as on a web page's original look, it is dimmed.
    var isAvailable = true
    @AppStorage(PageKey.textSize) private var textSize = PageStyle().textSize
    @Environment(\.interfaceTextSize) private var interfaceSize

    var body: some View {
        CornerButtonGroup {
            Menu {
                TextSizeOptions()
            } label: {
                HStack(spacing: 6) {
                    Text("\(PageStyle.nearestTextSize(textSize)) pt").monospacedDigit()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9 * InterfaceStyle.scale(for: interfaceSize), weight: .semibold))
                }
                .padding(.horizontal, 6)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Text Size")
            .accessibilityLabel("Text Size")
            .accessibilityValue("\(PageStyle.nearestTextSize(textSize)) pt")
            .accessibilityIdentifier("PageTextSize")
        }
        .disabled(!isAvailable)
    }
}

/// What the text size menu holds: the page's sizes with the current one ticked, Make Text Bigger and Make Text Smaller,
/// then Standard Width and Full Width. The corner's control and the More menu's Text Size submenu (where the person has
/// turned the control off in Settings > Editor) show the same entries.
struct TextSizeOptions: View {
    @AppStorage(PageKey.textSize) private var textSize = PageStyle().textSize
    @AppStorage(PageKey.fullWidth) private var fullWidth = PageStyle().fullWidth

    var body: some View {
        let zoom = TextZoom.page
        Picker("Text Size", selection: Binding(get: { PageStyle.nearestTextSize(textSize) }, set: { textSize = $0 })) {
            ForEach(PageStyle.textSizes, id: \.self) { size in Text("\(size) pt").tag(size) }
        }
        .pickerStyle(.inline)
        .labelsHidden()
        Divider()
        Button("Make Text Bigger", systemImage: "textformat.size.larger") { zoom.apply(.bigger) }
            .disabled(zoom.size(after: .bigger, from: textSize) == nil)
        Button("Make Text Smaller", systemImage: "textformat.size.smaller") { zoom.apply(.smaller) }
            .disabled(zoom.size(after: .smaller, from: textSize) == nil)
        Divider()
        Picker("Page Width", selection: $fullWidth) {
            Text("Standard Width").tag(false)
            Text("Full Width").tag(true)
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}
