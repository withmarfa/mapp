import SwiftUI

/// Opens the Change Type button's menu command as a value panel, for the items a window asked it for. The command has no
/// value on the page to open under, so the panel opens at the top middle of the window, as a command palette does; the
/// page's type chip opens the same panel under itself.
struct TypeChangePanel: ViewModifier {
    let details: DetailsPresentation
    @CurrentLibrary private var library
    @State private var anchor = ValueEditAnchorBox()

    func body(content: Content) -> some View {
        content
            .background(ValueEditAnchor(box: anchor))
            .onChange(of: details.typeChange?.id) {
                guard let request = details.typeChange else { return }
                details.typeChange = nil
                present(request)
            }
    }

    private func present(_ asked: TypeChangeRequest) {
        guard let window = anchor.view?.window, let content = window.contentView else { return }
        var request = ValueEditRequest(kind: .type, library: library, item: asked.ids.count == 1 ? asked.ids.first : nil, undoManager: asked.undoManager)
        request.items = asked.ids
        request.isCentered = true
        request.needsValues = { [weak details] type in
            details?.typeValues = TypeValuesRequest(ids: asked.ids, type: type, undoManager: asked.undoManager)
        }
        let top: CGFloat = 96
        let rect = NSRect(x: content.bounds.midX, y: content.isFlipped ? top : content.bounds.height - top, width: 0, height: 0)
        ValueEditPresenter.shared.present(request, anchor: content, rect: rect)
    }
}

/// Asks for the Change Type panel for the items, in the window whose presentation it is given.
struct TypeChangeButton: View {
    @CurrentLibrary private var library
    let ids: Set<ItemID>
    let details: DetailsPresentation?
    let undoManager: UndoManager?

    var body: some View {
        Button("Change Type…", systemImage: "square.on.square") {
            details?.typeChange = TypeChangeRequest(ids: ids, undoManager: undoManager)
        }
        .disabled(details == nil || !library.offersTypeChange(for: ids))
    }
}
