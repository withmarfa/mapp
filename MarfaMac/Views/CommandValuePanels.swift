import SwiftUI

/// Opens the value panel a menu, toolbar or palette command asks for (Change Type, Add Tag, Add to Collection), for the
/// items a window asked it for. These commands have no value on the page to open under, so the panel opens at the top
/// middle of the window, as a command palette does; the page's own rows open the same panels under themselves.
struct CommandValuePanels: ViewModifier {
    let details: DetailsPresentation
    @CurrentLibrary private var library
    @State private var anchor = ValueEditAnchorBox()

    func body(content: Content) -> some View {
        content
            .background(ValueEditAnchor(box: anchor))
            .onChange(of: details.typeChange?.id) {
                guard let request = details.typeChange else { return }
                details.typeChange = nil
                present(.type, for: request.ids, undoManager: request.undoManager)
            }
            .onChange(of: details.tagRequest?.id) {
                guard let request = details.tagRequest else { return }
                details.tagRequest = nil
                present(.tags, for: request.ids, undoManager: request.undoManager)
            }
            .onChange(of: details.collectionPick?.id) {
                guard let request = details.collectionPick else { return }
                details.collectionPick = nil
                present(.collections, for: request.ids, undoManager: request.undoManager)
            }
    }

    private func present(_ kind: ValueEditKind, for ids: Set<ItemID>, undoManager: UndoManager?) {
        guard let window = anchor.view?.window, let content = window.contentView else { return }
        var request = ValueEditRequest(kind: kind, library: library, item: ids.count == 1 ? ids.first : nil, undoManager: undoManager)
        request.items = ids
        request.isCentered = true
        if kind == .type {
            request.needsValues = { [weak details] type in
                details?.typeValues = TypeValuesRequest(ids: ids, type: type, undoManager: undoManager)
            }
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
    var shortcuts: ShortcutBindings?

    var body: some View {
        Button("Change Type…", systemImage: "square.on.square") {
            details?.typeChange = TypeChangeRequest(ids: ids, undoManager: undoManager)
        }
        .shortcut(.changeType, shortcuts)
        .disabled(details == nil || !library.offersTypeChange(for: ids))
    }
}
