import AppKit
import SwiftUI

enum InterfaceKey {
    static let textSize = "interfaceTextSize"
    /// The width the person last gave the right sidebar, kept across layouts and launches.
    static let inspectorWidth = "inspectorWidth"
    /// Whether the inspector's Details section is open, kept across items and launches.
    static let inspectorDetailsOpen = "inspectorDetailsOpen"
    /// Whether the inspector's Properties, Relationships, Links in This Page, Linked From and Tags sections are open, kept across items
    /// and launches.
    static let inspectorPropertiesOpen = "inspectorPropertiesOpen"
    static let inspectorRelationshipsOpen = "inspectorRelationshipsOpen"
    static let inspectorLinksInPageOpen = "inspectorLinksInPageOpen"
    static let inspectorLinkedFromOpen = "inspectorLinkedFromOpen"
    static let inspectorTagsOpen = "inspectorTagsOpen"
    static let inspectorOutlineOpen = "inspectorOutlineOpen"
    static let inspectorAttachmentsOpen = "inspectorAttachmentsOpen"
    static let inspectorCollectionsOpen = "inspectorCollectionsOpen"
    static let inspectorAppOpen = "inspectorAppOpen"
    /// Whether the window's toolbar shows a note's or item's title once the page's header has scrolled away.
    static let showsScrolledTitle = "showsScrolledTitle"
    /// What the toolbar's items show, chosen under Show in Customize Toolbar.
    static let toolbarLabelStyle = "toolbarLabelStyle"
    /// Whether a note's or item's page backs the toolbar with a blurred band while content scrolls under it.
    static let showsPageToolbarBackground = "showsPageToolbarBackground"
    /// Whether the panels that edit a value are glass or a solid color.
    static let valuePanelStyle = "valuePanelStyle"
    static let all = [valuePanelStyle, textSize, inspectorWidth, inspectorDetailsOpen, inspectorPropertiesOpen, inspectorRelationshipsOpen, inspectorLinksInPageOpen, inspectorLinkedFromOpen, inspectorTagsOpen, inspectorOutlineOpen, inspectorAttachmentsOpen, inspectorCollectionsOpen, inspectorAppOpen, showsScrolledTitle, toolbarLabelStyle, showsPageToolbarBackground] + ColumnWidth.allCases.map(\.key)
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

struct ValuePanelOptions: View {
    @AppStorage(InterfaceKey.valuePanelStyle) private var style = ValuePanelStyle.standard

    var body: some View {
        Picker("Value Panels", selection: $style) {
            Text("Glass").tag(ValuePanelStyle.glass)
            Text("Solid").tag(ValuePanelStyle.solid)
        }
        .accessibilityIdentifier("ValuePanelStyle")
    }
}
