import AppKit
import SwiftUI

enum InterfaceKey {
    static let textSize = "interfaceTextSize"
    /// The width the person last gave the right sidebar, kept across layouts and launches.
    static let inspectorWidth = "inspectorWidth"
    /// Whether the window's toolbar shows an item's title once the page's header has scrolled away.
    static let showsScrolledTitle = "showsScrolledTitle"
    /// Whether Back and Forward stand over the sidebar.
    static let showsSidebarHistory = "showsSidebarHistory"
    /// Whether an item's page backs the toolbar with a blurred band while content scrolls under it.
    static let showsPageToolbarBackground = "showsPageToolbarBackground"
    /// Whether the panels that edit a value are glass or a solid color.
    static let valuePanelStyle = "valuePanelStyle"
    /// What the command palette, Search Items and the new item stand on.
    static let paletteMaterial = "paletteMaterial"
    static let all = [valuePanelStyle, paletteMaterial, textSize, inspectorWidth, showsScrolledTitle, showsSidebarHistory, showsPageToolbarBackground] + ColumnWidth.allCases.map(\.key)
}

/// What a value panel is made of. Glass lets the page show through; Solid is the window's own color.
enum ValuePanelStyle: String, CaseIterable, Identifiable {
    case glass
    case solid

    static let standard = ValuePanelStyle.glass

    static func stored(in defaults: UserDefaults = .standard) -> ValuePanelStyle {
        defaults.string(forKey: InterfaceKey.valuePanelStyle).flatMap(Self.init(rawValue:)) ?? standard
    }

    var id: Self { self }
}

/// What the floating panels (the command palette, Search Items and the new item) are made of. Glass is the system's
/// Liquid Glass; Translucent is the material the system gives popovers; Solid is the window's own color.
enum PaletteMaterial: String, CaseIterable, Identifiable {
    case glass
    case translucent
    case solid

    static let standard = PaletteMaterial.glass

    var id: Self { self }
}

/// The right sidebar's width in every window: 300, which the person can drag out to the widest.
enum PanelWidth {
    static let standard: CGFloat = 300
    static let widest: CGFloat = 440
}

enum InterfaceStyle {
    static let defaultTextSize = Typography.primary
    static let textSizes = [11, 12, 13, 14, 15, 16, 18, 20, 24]

    static func scale(for textSize: Int) -> CGFloat {
        CGFloat(min(24, max(11, textSize))) / CGFloat(defaultTextSize)
    }

    static func font(_ style: NSFont.TextStyle, textSize: Int) -> NSFont {
        if style == .body { return .systemFont(ofSize: CGFloat(defaultTextSize) * scale(for: textSize)) }
        let font = NSFont.preferredFont(forTextStyle: style)
        return NSFontManager.shared.convert(font, toSize: font.pointSize * scale(for: textSize))
    }

    static let primaryFont = Font.system(size: CGFloat(Typography.primary))
    static let captionFont = Font.system(size: Typography.caption)
}

extension EnvironmentValues {
    @Entry var interfaceTextSize = InterfaceStyle.defaultTextSize
}

private struct InterfaceTextStyle: ViewModifier {
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize

    func body(content: Content) -> some View {
        content
            .environment(\.interfaceTextSize, textSize)
            .font(InterfaceStyle.primaryFont.scaled(by: InterfaceStyle.scale(for: textSize)))
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
