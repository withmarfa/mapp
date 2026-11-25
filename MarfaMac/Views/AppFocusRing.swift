import SwiftUI

/// The app's own keyboard focus ring in place of the system's: a gray ring of `ChipLooks.focusRingWidth` points, drawn just
/// outside the control's edge in the control's own shape. One modifier serves every field and button that takes the
/// keyboard, so no control shows the system's blue ring.
struct AppFocusRing<RingShape: Shape>: ViewModifier {
    let shape: RingShape
    /// Set where the caller already tracks the control's focus (`@FocusState`); nil where the ring follows its own.
    let isFocused: Bool?

    @FocusState private var ownFocus: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        Group {
            if isFocused == nil {
                content.focused($ownFocus)
            } else {
                content
            }
        }
        .focusEffectDisabled()
        .overlay {
            if isFocused ?? ownFocus {
                shape
                    .stroke(ChipLooks.defaults.focusRing(for: scheme), lineWidth: ChipLooks.defaults.focusRingWidth)
                    .padding(-ChipLooks.defaults.focusRingWidth / 2)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    /// Draws the app's focus ring round a field. Put it after the field's own background and padding, so the ring follows
    /// the edge the person sees. Pass `isFocused` where the field already has a focus state, so one field never has two.
    func appFocusRing(_ shape: some Shape = RoundedRectangle(cornerRadius: 7, style: .continuous), isFocused: Bool? = nil) -> some View {
        modifier(AppFocusRing(shape: shape, isFocused: isFocused))
    }
}
