import AppKit
import SwiftUI

enum InterfaceKey {
    static let textSize = "interfaceTextSize"
    /// Whether the inspector's Details section is open, kept across items and launches.
    static let inspectorDetailsOpen = "inspectorDetailsOpen"
    static let all = [textSize, inspectorDetailsOpen]
}

enum InterfaceStyle {
    static let defaultTextSize = 13
    static let textSizes = [11, 12, 13, 14, 15, 16, 18, 20, 24]

    static func scale(for textSize: Int) -> CGFloat {
        CGFloat(min(24, max(11, textSize))) / CGFloat(defaultTextSize)
    }

    static func font(_ style: NSFont.TextStyle, textSize: Int) -> NSFont {
        let font = NSFont.preferredFont(forTextStyle: style)
        return NSFontManager.shared.convert(font, toSize: font.pointSize * scale(for: textSize))
    }
}

extension EnvironmentValues {
    @Entry var interfaceTextSize = InterfaceStyle.defaultTextSize
}

private struct InterfaceTextStyle: ViewModifier {
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize

    func body(content: Content) -> some View {
        content
            .environment(\.interfaceTextSize, textSize)
            .font(Font.body.scaled(by: InterfaceStyle.scale(for: textSize)))
    }
}

private struct InterfaceFont: ViewModifier {
    @Environment(\.interfaceTextSize) private var textSize
    let font: Font

    func body(content: Content) -> some View {
        content.font(font.scaled(by: InterfaceStyle.scale(for: textSize)))
    }
}

extension View {
    func interfaceTextStyle() -> some View { modifier(InterfaceTextStyle()) }

    func interfaceFont(_ font: Font) -> some View {
        modifier(InterfaceFont(font: font))
    }
}

struct InterfaceTextOptions: View {
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize

    var body: some View {
        Picker("Base Text Size", systemImage: "textformat.size", selection: $textSize) {
            ForEach(InterfaceStyle.textSizes, id: \.self) { size in
                Text("\(size) pt").tag(size)
            }
        }
        .accessibilityIdentifier("InterfaceTextSize")
    }
}
