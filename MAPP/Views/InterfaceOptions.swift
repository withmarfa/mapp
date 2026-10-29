import AppKit
import SwiftUI

enum InterfaceKey {
    static let textSize = "interfaceTextSize"
    /// Whether the inspector's Details section is open, kept across items and launches.
    static let inspectorDetailsOpen = "inspectorDetailsOpen"
    /// Whether the inspector's Linked From section is open, kept across items and launches.
    static let inspectorLinkedFromOpen = "inspectorLinkedFromOpen"
    /// Whether the window's toolbar shows a note's or item's title once the page's header has scrolled away.
    static let showsScrolledTitle = "showsScrolledTitle"
    /// Whether a note's or item's page backs the toolbar with a blurred band while content scrolls under it.
    static let showsPageToolbarBackground = "showsPageToolbarBackground"
    static let all = [textSize, inspectorDetailsOpen, inspectorLinkedFromOpen, showsScrolledTitle, showsPageToolbarBackground] + ColumnWidth.allCases.map(\.key)
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

/// What the toolbar does as a note's or item's page scrolls beneath it. Both are on until turned off.
struct ToolbarOptions: View {
    @AppStorage(InterfaceKey.showsScrolledTitle) private var showsTitle = true
    @AppStorage(InterfaceKey.showsPageToolbarBackground) private var showsBackground = true

    var body: some View {
        Toggle("Show Title When Scrolling", isOn: $showsTitle)
            .toggleStyle(.switch)
            .accessibilityIdentifier("ToolbarScrolledTitle")
        Toggle("Show Toolbar Background When Scrolling", isOn: $showsBackground)
            .toggleStyle(.switch)
            .accessibilityIdentifier("ToolbarPageBackground")
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
