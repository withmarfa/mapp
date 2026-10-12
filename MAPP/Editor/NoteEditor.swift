import SwiftUI

/// WebKit scrolls the item's header and the note as one page; the toolbar, a banner and the find bar cover its top.
struct NoteEditor: NSViewRepresentable {
    let controller: EditorController
    let topInset: CGFloat

    func makeNSView(context: Context) -> EditorContainer {
        controller.container
    }

    func updateNSView(_ container: EditorContainer, context: Context) {
        container.topInset = topInset
    }

    // WebKit lays out badly at fractional sizes, so the proposal is rounded down to whole points.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EditorContainer, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width.rounded(.down), height: height.rounded(.down))
    }
}
