import SwiftUI

/// What a button is for. `outline` is the menu button's look, a white button with a hairline and a chevron.
enum AppButtonRole {
    case primary, secondary, plain, destructive, outline
}

enum AppButtonSize {
    case small, regular

    /// Height, corner radius, side padding and text size at the default interface text size.
    fileprivate var height: CGFloat { self == .small ? 22 : 28 }
    fileprivate var radius: CGFloat { self == .small ? 7 : 9 }
    fileprivate var padding: CGFloat { self == .small ? 9 : 12 }
    fileprivate var textSize: CGFloat { self == .small ? 12 : 13 }
}

/// The one button the app draws itself (`docs/components.md`): a rounded rectangle, or a circle for an icon-only button,
/// in the fills of the design system's `.m-b`. The toolbar's glass buttons and the system's menus, alerts and
/// controls stay the system's.
struct AppButtonStyle: ButtonStyle {
    let role: AppButtonRole
    let size: AppButtonSize
    let isIcon: Bool

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, role: role, size: size, isIcon: isIcon)
    }

    private struct Content: View {
        let configuration: Configuration
        let role: AppButtonRole
        let size: AppButtonSize
        let isIcon: Bool
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.interfaceTextSize) private var textSize

        var body: some View {
            let scale = InterfaceStyle.scale(for: textSize)
            let height = size.height * scale
            let shape = isIcon ? AnyShape(Circle()) : AnyShape(.rect(cornerRadius: size.radius * scale, style: .continuous))
            let pressed = configuration.isPressed
            let hovered = isHovered && isEnabled
            HStack(spacing: 6) {
                configuration.label
                if role == .outline {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9 * scale, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
                .font(.system(size: size.textSize * scale, weight: role == .outline ? .regular : .medium))
                .foregroundStyle(foreground(hovered: hovered || pressed))
                .padding(.horizontal, isIcon ? 0 : size.padding * scale)
                .frame(minWidth: isIcon ? height : nil)
                .frame(height: height)
                .background(shape.fill(fill(hovered: hovered, pressed: pressed)))
                .overlay {
                    if role == .outline { shape.stroke(Color.primary.opacity(0.12), lineWidth: 1) }
                }
                .contentShape(shape)
                .overlay {
                    if isFocused { focusRing(radius: size.radius * scale) }
                }
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { isHovered = $0 }
        }

        /// A gray ring of 3 points drawn outside the button's edge, as the design system's focus state draws it.
        @ViewBuilder
        private func focusRing(radius: CGFloat) -> some View {
            let color = Color.primary.opacity(0.26)
            if isIcon {
                Circle().stroke(color, lineWidth: 3).padding(-1.5)
            } else {
                RoundedRectangle(cornerRadius: radius + 1.5, style: .continuous).stroke(color, lineWidth: 3).padding(-1.5)
            }
        }

        private var isDark: Bool { colorScheme == .dark }
        private var red: Color { isDark ? Color(red: 1, green: 0.388, blue: 0.412) : Color(red: 0.898, green: 0.282, blue: 0.302) }
        private var redText: Color { isDark ? Color(red: 1, green: 0.584, blue: 0.573) : Color(red: 0.706, green: 0.137, blue: 0.094) }

        private func foreground(hovered: Bool) -> Color {
            switch role {
            case .primary: .white
            case .destructive: redText
            case .plain: hovered ? Color.primary.opacity(0.847) : Color.primary.opacity(0.5)
            case .secondary, .outline: Color.primary.opacity(0.847)
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
            case .outline:
                (isDark ? Color.white.opacity(0.1) : .white).mix(with: .primary, by: pressed ? 0.09 : hovered ? 0.04 : 0)
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

    /// Draws a menu as the outlined button among the app's buttons: its label and a chevron, as tall as the buttons beside it.
    func appMenu(size: AppButtonSize = .regular) -> some View {
        menuStyle(.button)
            .menuIndicator(.hidden)
            .appButton(.outline, size: size)
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
