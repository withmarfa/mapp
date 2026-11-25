import AppKit
import SwiftUI

extension View {
    /// Shows the card of the item `id` after the pointer rests on this view, and takes it away when it leaves. The view
    /// takes no click or key for it, and the card none from the person (`LinkCardPresenter`).
    func linkCard(of id: ItemID, in library: any ItemLibrary) -> some View {
        background(LinkCardTracker(id: id, library: library))
    }
}

private struct LinkCardTracker: NSViewRepresentable {
    let id: ItemID
    let library: any ItemLibrary

    func makeNSView(context: Context) -> TrackerView { TrackerView() }

    func updateNSView(_ view: TrackerView, context: Context) {
        view.id = id
        view.library = library
    }

    /// An empty view over the row's frame that hears the pointer enter and leave through a tracking area, so it covers
    /// the row without taking its clicks.
    final class TrackerView: NSView {
        var id: ItemID?
        var library: (any ItemLibrary)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        }

        override func mouseEntered(with event: NSEvent) {
            guard let id, let library, let window else { return }
            let anchor = LinkCardAnchor(rect: window.convertToScreen(convert(bounds, to: nil)), window: window)
            LinkCardPresenter.shared.rest(library: library, at: anchor) { id }
        }

        override func mouseExited(with event: NSEvent) {
            LinkCardPresenter.shared.end()
        }
    }
}
