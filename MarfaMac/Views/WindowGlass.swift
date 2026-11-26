import SwiftUI

extension View {
    /// Glass for a control drawn in the content, whose icons and words follow the window's active state as the toolbar's do
    /// (`controlForeground`).
    func windowGlass<S: Shape>(_ glass: Glass = .regular, in shape: S) -> some View {
        controlForeground().glassEffect(glass, in: shape)
    }

    /// The label color of a control in the content: primary while the window is the active one, tertiary while it is not,
    /// as the system's toolbar buttons dim, and tertiary too while the control is disabled.
    func controlForeground(isEnabled: Bool = true) -> some View { modifier(ControlForeground(isEnabled: isEnabled)) }
}

private struct ControlForeground: ViewModifier {
    let isEnabled: Bool
    @Environment(\.appearsActive) private var appearsActive

    func body(content: Content) -> some View {
        content.foregroundStyle(appearsActive && isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
    }
}
