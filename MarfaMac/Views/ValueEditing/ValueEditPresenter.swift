import AppKit

/// One open value editor: the panel under a value. The presenter keeps at most one, whoever asks.
@MainActor
protocol ValueEditSession: PanelSession {
    var request: ValueEditRequest { get }
    var model: ValueEditModel { get }
    /// The value the editor is under moved within the anchor, to `rect`: follow it.
    func valueMoved(to rect: NSRect)
}

/// Opens a value in an editor under it, for the inspector's rows and the page's property rows alike: each gives what is
/// edited, a view and a rectangle in it. Nothing differs by caller.
@MainActor
final class ValueEditPresenter {
    static let shared = ValueEditPresenter()

    typealias Factory = @MainActor (ValueEditRequest, NSView, NSRect?) -> any ValueEditSession

    /// Opens a type's page in Settings > Types, which a status panel's Edit Statuses asks for. The app sets it once.
    var editType: ((TypeID) -> Void)?

    private let panels = PanelPresenter()
    private let makeSession: Factory

    init(makeSession: @escaping Factory = ValueEditPresenter.system) {
        self.makeSession = makeSession
    }

    var session: (any ValueEditSession)? { panels.session as? any ValueEditSession }

    var isOpen: Bool { panels.isOpen }

    /// Opens the editor for `request` under `rect` of `anchor` (its bounds where nil), or closes it where it is the
    /// editor already open. Nothing opens for a value the item cannot take.
    func present(_ request: ValueEditRequest, anchor: NSView, rect: NSRect? = nil, now: Date = .now) {
        panels.present(target: request.target, anchor: anchor, now: now) { anchor in
            let new = makeSession(request, anchor, rect)
            guard new.model.isEditable else { return nil }
            new.model.close = { [weak self, weak new] in
                guard let self, let new, panels.session === new else { return }
                dismiss()
            }
            return new
        }
    }

    /// Closes the editor open, if any. What was typed in it is written or handed back (`ValueEditModel.finish`) unless
    /// the person `cancelled` it, with Escape.
    func dismiss(restoringFocus: Bool = true, cancelled: Bool = false) {
        panels.dismiss(restoringFocus: restoringFocus, cancelled: cancelled)
    }

    /// The app is quitting or changing library: the editor open ends as it does on a click elsewhere, so what was typed
    /// in it is written to the library it came from or handed back, never lost.
    func handOff() { dismiss(restoringFocus: false) }

    /// The value of `row` of `item` moved within the view that anchors its editor, as a page's rows do when one is set
    /// for the first time. An editor open for another value stays where it is.
    func valueMoved(item: ItemID, row: String, to rect: NSRect) {
        guard let session, session.request.target == item.rawValue + "#" + row else { return }
        session.valueMoved(to: rect)
    }

    /// The item on show changed: an editor for another item is for a value that is no longer there.
    func itemChanged(to id: ItemID?) {
        guard let item = session?.request.item, item != id else { return }
        dismiss(restoringFocus: false)
    }

    /// A view that anchored an editor has left its window.
    func anchorLeft(_ view: NSView) {
        if session?.anchor === view { dismiss(restoringFocus: false) }
    }

    /// The editor a value opens in: the panel under it.
    static func system(_ request: ValueEditRequest, anchor: NSView, rect: NSRect?) -> any ValueEditSession {
        ValueEditPanelSession(request, anchor: anchor, rect: rect)
    }
}

extension ValueEditSession {
    var target: String { request.target }

    func finish(cancelled: Bool) { model.finish(cancelled: cancelled) }

    /// Whether the editor took the key, which then goes no further.
    func handleKey(_ event: NSEvent) -> Bool {
        // The search and the name field take every other key, and the map none.
        if case .location = model.kind { return false }
        if let text = window?.firstResponder as? NSTextView, text.hasMarkedText() { return false }
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if model.kind.isTyped {
            // The field takes every key but Return, which writes; Option or Shift with it starts a new line.
            guard isReturn, event.modifierFlags.intersection([.shift, .option]).isEmpty else { return false }
            model.submitTyped()
            return true
        }
        // The time field takes the arrows and Return itself.
        if case .date = model.kind, window?.firstResponder is NSTextView { return false }
        switch event.keyCode {
        // Not on a repeat: holding Backspace to clear the search must not go on to remove the chips.
        case 51 where model.hasSearch && !event.isARepeat && event.modifierFlags.intersection([.command, .control, .option]).isEmpty:
            return model.removeLastChip()
        case 125:
            model.move(by: 1)
            return true
        case 126:
            model.move(by: -1)
            return true
        case _ where isReturn:
            if case .date = model.kind, model.activeRow == nil { return false }
            model.submitTyped()
            return true
        default:
            break
        }
        let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        if plain, !model.hasSearch, let characters = event.charactersIgnoringModifiers, characters.unicodeScalars.allSatisfy({ !$0.properties.isWhitespace && $0.value >= 0x21 && $0.value < 0xF700 }) {
            model.typeAhead(characters)
            return true
        }
        return false
    }
}
