import AppKit
import SwiftUI

/// Opens one panel at a time under a chip or the +, in a child window on the system's glass, as a value panel opens: the
/// same `PanelPresenter` keeps and watches it. It closes on a click outside, Escape, a scroll, the app going to the
/// background and the window resizing, and calls `onClose` then.
@MainActor
final class FilterPanelPresenter {
    static let shared = FilterPanelPresenter()

    private let panels = PanelPresenter()

    var isOpen: Bool { panels.isOpen }

    /// Whether the panel open is the one `key` names.
    func isOpen(for key: String) -> Bool { panels.isOpen(for: key) }

    /// Opens `content` under `anchor`, or closes it where `key` is the panel already open or was just closed by the click
    /// that asks to open it.
    func present<Content: View>(key: String, anchor: NSView?, width: CGFloat, onClose: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        panels.present(target: key, anchor: anchor) { anchor in
            FilterPanelSession(key: key, anchor: anchor, width: width, onClose: onClose, content: AnyView(content()))
        }
    }

    /// Closes the panel open, if any, and tells its owner.
    func dismiss(restoringFocus: Bool = true) {
        panels.dismiss(restoringFocus: restoringFocus)
    }
}

/// A filter's panel: a child window under its chip, as tall as its content.
@MainActor
final class FilterPanelSession: PanelSession {
    let target: String
    let anchor: NSView
    private let content: AnyView
    private let width: CGFloat
    private let onClose: () -> Void
    private var height: CGFloat = 120
    private var panel: ValueEditPanel?
    private weak var parent: NSWindow?
    private var layoutPending = false
    /// Follows the window's appearance, so a panel left open does not keep the one it opened in.
    private var appearanceWatch: NSKeyValueObservation?

    var window: NSWindow? { panel }

    init(key: String, anchor: NSView, width: CGFloat, onClose: @escaping () -> Void, content: AnyView) {
        target = key
        self.anchor = anchor
        self.onClose = onClose
        self.content = content
        self.width = width * InterfaceStyle.scale(for: UserDefaults.standard.object(forKey: InterfaceKey.textSize) as? Int ?? InterfaceStyle.defaultTextSize)
    }

    func open() {
        guard let parent = anchor.window else { return }
        self.parent = parent
        let measured = content
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { [weak self] in
                self?.height = $0
                self?.layoutSoon()
            }
            .interfaceTextStyle()
        let host = NSHostingView(rootView: measured)
        host.sizingOptions = []
        let panel = ValueEditPanel.make(holding: host, over: parent)
        self.panel = panel
        layout()
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        appearanceWatch = parent.observe(\.effectiveAppearance) { [weak self] window, _ in
            MainActor.assumeIsolated { self?.panel?.appearance = window.effectiveAppearance }
        }
    }

    func close(restoringFocus: Bool) {
        guard let panel else { return }
        appearanceWatch = nil
        self.panel = nil
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if restoringFocus { parent?.makeKey() }
        onClose()
    }

    func anchorMoved() { layoutSoon() }

    func finish(cancelled: Bool) {}

    /// The panel's own controls take every key but Escape, which the presenter handles.
    func handleKey(_ event: NSEvent) -> Bool { false }

    private func layoutSoon() {
        guard !layoutPending else { return }
        layoutPending = true
        DispatchQueue.main.async { [weak self] in
            self?.layoutPending = false
            self?.layout()
        }
    }

    private func layout() {
        guard let panel, let parent, let under = anchor.screenRect(of: nil) else { return }
        let visible = ValueEditPanel.visibleArea(of: parent, around: under)
        let placement = ValuePanelFrame.placement(
            anchor: under, visible: visible, contentHeight: height, floor: width, ceiling: width, gap: ValueEditMetrics.gap, fitting: width)
        if panel.frame != placement.frame {
            panel.setFrame(placement.frame, display: true)
            panel.invalidateShadow()
        }
        panel.contentView?.frame = NSRect(origin: .zero, size: placement.frame.size)
    }
}
