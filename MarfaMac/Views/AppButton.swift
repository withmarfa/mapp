import SwiftUI

enum AppButtonRole {
    case primary, secondary, plain, destructive
}

/// How a menu button reads: a pop-up that chooses a value shows two arrows, a pull-down menu of commands shows one.
enum AppMenuKind {
    case value, commands

    fileprivate var symbol: String { self == .value ? "chevron.up.chevron.down" : "chevron.down" }
}

/// The three heights of the button rule: a capsule at `regular` and `large`, 7-point corners at `small`.
enum AppButtonSize {
    case small, regular, large

    /// Height, side padding and text size at the default interface text size.
    fileprivate var height: CGFloat {
        switch self {
        case .small: 24
        case .regular: 28
        case .large: 36
        }
    }
    fileprivate var padding: CGFloat {
        switch self {
        case .small: 9
        case .regular: 12
        case .large: 18
        }
    }
    fileprivate var textSize: CGFloat { self == .small ? 12 : 13 }
    fileprivate var isCapsule: Bool { self != .small }
    fileprivate var cornerRadius: CGFloat { 7 }
}

/// The one button the app draws itself (`docs/look.md`): a capsule at 28 and 36 points, a rounded rectangle at 24,
/// and a circle for a button whose label is only a symbol, in the fills of the design system's `.m-b`. The toolbar's glass
/// buttons and the system's menus, alerts and controls stay the system's.
struct AppButtonStyle: ButtonStyle {
    let role: AppButtonRole
    let size: AppButtonSize
    let isIcon: Bool
    /// Set for a menu button: the arrow it ends in.
    var menu: AppMenuKind?

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, role: role, size: size, isIcon: isIcon, menu: menu)
    }

    /// The edge of a button and of its keyboard focus ring, which follows it: a circle, a capsule or 7-point corners.
    static func shape(size: AppButtonSize, isIcon: Bool, scale: CGFloat = 1) -> AnyShape {
        if isIcon { return AnyShape(Circle()) }
        if size.isCapsule { return AnyShape(Capsule(style: .circular)) }
        return AnyShape(.rect(cornerRadius: size.cornerRadius * scale, style: .continuous))
    }

    /// The ring of `AppFocusRing`, drawn outside the button's edge, as the design system's focus state draws it.
    static func focusRing(_ shape: AnyShape) -> some View {
        FocusRingStroke(shape: shape)
    }

    private struct FocusRingStroke: View {
        let shape: AnyShape
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            shape
                .stroke(ChipLooks.defaults.focusRing(for: scheme), lineWidth: ChipLooks.defaults.focusRingWidth)
                .padding(-ChipLooks.defaults.focusRingWidth / 2)
        }
    }

    private struct Content: View {
        let configuration: Configuration
        let role: AppButtonRole
        let size: AppButtonSize
        let isIcon: Bool
        let menu: AppMenuKind?
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.interfaceTextSize) private var textSize

        /// A menu's label is regular, as the system's pop-ups are; a button's is medium.
        private var weight: Font.Weight { menu == nil ? .medium : .regular }

        var body: some View {
            let scale = InterfaceStyle.scale(for: textSize)
            let height = size.height * scale
            let shape = AppButtonStyle.shape(size: size, isIcon: isIcon, scale: scale)
            let pressed = configuration.isPressed
            let hovered = isHovered && isEnabled
            HStack(spacing: 6 * scale) {
                configuration.label
                if let menu {
                    Image(systemName: menu.symbol)
                        .font(.system(size: size.textSize * 0.8 * scale, weight: weight))
                        .foregroundStyle(.secondary)
                }
            }
                .font(.system(size: size.textSize * scale, weight: weight))
                .foregroundStyle(foreground(hovered: hovered || pressed))
                .padding(.horizontal, isIcon ? 0 : size.padding * scale)
                .frame(minWidth: isIcon ? height : nil)
                .frame(height: height)
                .background(shape.fill(fill(hovered: hovered, pressed: pressed)))
                .contentShape(shape)
                .overlay {
                    if isFocused { AppButtonStyle.focusRing(shape) }
                }
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { isHovered = $0 }
        }

        private var isDark: Bool { colorScheme == .dark }
        private var red: Color { isDark ? Color(red: 1, green: 0.388, blue: 0.412) : Color(red: 0.898, green: 0.282, blue: 0.302) }
        private var redText: Color { isDark ? Color(red: 1, green: 0.584, blue: 0.573) : Color(red: 0.706, green: 0.137, blue: 0.094) }

        private func foreground(hovered: Bool) -> Color {
            switch role {
            case .primary: .white
            case .destructive: redText
            case .plain: hovered ? Color.primary.opacity(0.847) : Color.primary.opacity(0.5)
            case .secondary: Color.primary.opacity(0.847)
            }
        }

        private func fill(hovered: Bool, pressed: Bool) -> Color {
            switch role {
            case .primary:
                pressed ? Color.accentColor.mix(with: .black, by: 0.24) : hovered ? Color.accentColor.mix(with: .black, by: 0.12) : .accentColor
            case .secondary:
                Color.primary.opacity(pressed ? 0.15 : hovered ? 0.10 : 0.065)
            case .plain:
                Color.primary.opacity(pressed ? 0.098 : hovered ? 0.047 : 0)
            case .destructive:
                red.opacity(pressed ? 0.22 : hovered ? 0.16 : 0.11)
            }
        }
    }
}

extension View {
    /// Draws a button as the app's one button style. `icon` is for a button whose label is only a symbol, which is round.
    func appButton(_ role: AppButtonRole, size: AppButtonSize = .regular, icon: Bool = false) -> some View {
        buttonStyle(AppButtonStyle(role: role, size: size, isIcon: icon))
            .focusEffectDisabled()
    }

    /// Draws a menu as a gray button with a label and an arrow, as tall as the buttons beside it. The caller says what the
    /// menu does: `.value` for a pop-up that chooses a value, `.commands` for a menu of commands.
    func appMenu(_ kind: AppMenuKind, role: AppButtonRole = .secondary, size: AppButtonSize = .regular) -> some View {
        menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(AppButtonStyle(role: role, size: size, isIcon: false, menu: kind))
            .focusEffectDisabled()
            .fixedSize()
    }
}

/// The label above a text field in a sheet, such as Name. The field keeps its own accessibility label.
struct FieldLabel: View {
    private let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title)
            .interfaceFont(.callout)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}
