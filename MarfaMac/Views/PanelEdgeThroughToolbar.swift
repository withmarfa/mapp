import SwiftUI

extension View {
    /// Draws the line between a page and its panel up through the toolbar's height as well, for a panel made with `inspector`.
    func panelEdgeThroughToolbar() -> some View { modifier(PanelEdgeThroughToolbar()) }
}

/// The system draws the panel's line only below the toolbar, where the panel's content starts, while the boards draw
/// the panel as a column of the full window height. In full screen the system's own line already reaches the top, so
/// nothing is added there.
private struct PanelEdgeThroughToolbar: ViewModifier {
    @Environment(\.displayScale) private var displayScale
    @State private var isFullScreen = false

    func body(content: Content) -> some View {
        content
            .background(FullScreenProbe(isFullScreen: $isFullScreen))
            .overlay(alignment: .topLeading) {
                if !isFullScreen {
                    Rectangle().fill(.separator).frame(width: 1 / displayScale, height: TopRowMetrics.lineHeight)
                        .ignoresSafeArea(.container, edges: .top)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
    }
}

/// Reports whether the window it is in is in full screen.
private struct FullScreenProbe: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ probe: Probe, context: Context) {
        probe.report = { new in if isFullScreen != new { isFullScreen = new } }
        probe.read()
    }

    final class Probe: NSView {
        var report: (Bool) -> Void = { _ in }
        private var observers: [any NSObjectProtocol] = []

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            guard let window else { return }
            for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.read() }
                })
            }
            read()
        }

        func read() { report(window?.styleMask.contains(.fullScreen) == true) }
    }
}
