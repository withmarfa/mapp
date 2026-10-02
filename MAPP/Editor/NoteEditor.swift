import SwiftUI

/// The editor receives only the region below the native item header; the find bar reserves space inside it.
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
