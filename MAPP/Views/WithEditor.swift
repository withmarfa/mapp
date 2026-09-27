import SwiftUI

/// Gives a window its editor, made once, when the window first shows. SwiftUI makes a view's value afresh each
/// time its parent's body runs, and a state's first value with it, and an editor is a web page.
struct WithEditor<Content: View>: View {
    @State private var editor: EditorController?
    @ViewBuilder let content: (EditorController) -> Content

    var body: some View {
        if let editor {
            content(editor)
        } else {
            Color.clear
                .onAppear { editor = EditorController() }
        }
    }
}

/// A window with nothing to show, which closes.
struct ClosingView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Color.clear
            .onAppear { dismiss() }
    }
}
