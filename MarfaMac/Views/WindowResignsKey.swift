import AppKit
import SwiftUI

extension View {
    /// Calls `action` once this view's window has stopped being the key window and stayed so, whether another
    /// window took the key or the app was put in the background. `action` is told whether the window that took the
    /// key belongs to this one (a sheet, a popover or another window it opened), which is not leaving it.
    func onWindowResignsKey(_ action: @escaping (_ keyWindowIsOwn: Bool) -> Void) -> some View {
        background(WindowResignsKey(action: action))
    }
}

private struct WindowResignsKey: NSViewRepresentable {
    let action: (Bool) -> Void

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ probe: Probe, context: Context) { probe.action = action }
    static func dismantleNSView(_ probe: Probe, coordinator: ()) { probe.stop() }

    final class Probe: NSView {
        var action: ((Bool) -> Void)?
        private var observer: (any NSObjectProtocol)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resigned() }
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func stop() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }

        /// Which window takes the key is not known while the old one resigns, so it is looked at a turn later.
        private func resigned() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window, !window.isKeyWindow else { return }
                let key = NSApp.keyWindow
                action?(key.map { Self.belongs($0, to: window) } ?? false)
            }
        }

        private static func belongs(_ other: NSWindow, to window: NSWindow) -> Bool {
            other === window.attachedSheet || other.sheetParent === window || other.parent === window
                || window.childWindows?.contains(other) == true
        }
    }
}
