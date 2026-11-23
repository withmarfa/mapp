import SwiftUI

/// A toast as the design system's `Toast` draws it: a solid, rounded bar 44 points tall with an optional symbol, the
/// message, Undo where the action can be undone, and a close button (`docs/components.md`).
struct ToastView: View {
    let toast: ToastPresenter.Toast
    let presenter: ToastPresenter
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        HStack(spacing: 10 * scale) {
            if let symbol = toast.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14 * scale))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(toast.message)
                .font(.system(size: 13 * scale))
                .lineLimit(1)
                .padding(.trailing, 4 * scale)
            if toast.undo != nil {
                Button("Undo") { presenter.undo() }
                    .appButton(.primary, size: .small)
            }
            Button("Dismiss", systemImage: "xmark") { presenter.dismiss() }
                .labelStyle(.iconOnly)
                .appButton(.plain, size: .small, icon: true)
        }
        .padding(.leading, 16 * scale)
        .padding(.trailing, 8 * scale)
        .frame(height: 44 * scale)
        .background(.background, in: .rect(cornerRadius: 12 * scale, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12 * scale, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
        .shadow(color: .black.opacity(0.05), radius: 3, y: 2)
        .fixedSize()
        .onHover { presenter.hold($0) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(toast.message)
    }
}

/// Where a window's toast rises: at the foot of the content it covers, centered on it. Only the toast takes clicks.
private struct ToastHost: View {
    let presenter: ToastPresenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let toast = presenter.current {
                ToastView(toast: toast, presenter: presenter)
                    .id(toast.id)
                    .padding(.bottom, 22)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: presenter.current?.id)
        .onChange(of: presenter.current?.id) {
            if let message = presenter.current?.message { AccessibilityNotification.Announcement(message).post() }
        }
    }
}

private struct ToastOverlay: ViewModifier {
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?

    func body(content: Content) -> some View {
        content.overlay {
            if let details { ToastHost(presenter: details.toasts) }
        }
    }
}

extension View {
    /// Shows the window's toast over this view, which is the content column and never the sidebar.
    func toastOverlay() -> some View { modifier(ToastOverlay()) }
}
