import CoreGraphics
import Foundation

nonisolated enum Mark: String, Sendable {
    case bold, italic, strikethrough, code, link
}

nonisolated enum Block: Equatable, Sendable {
    case paragraph
    case heading(Int)
    case codeBlock
    case bulletList
    case orderedList
    case taskList
}

/// What sits under the caret, for the Format menu's checkmarks and the Edit menu's Undo and Redo.
nonisolated struct CaretState: Equatable, Sendable {
    var marks: Set<Mark> = []
    var block: Block = .paragraph
    /// One quote holds the whole selection; `block` is what sits inside it.
    var quoted = false
    var sourceMode = false
    var inTable = false
    var canUndo = false
    var canRedo = false
    var generation = -1
    var formats: [String: Bool] = [:]
    var tables: [String: Bool] = [:]
}

/// What the page tells the app, decoded from the JSON it posts to the `host` message handler.
nonisolated enum EditorMessage: Sendable {
    case ready
    case changed(String, generation: Int)
    case state(CaretState)
    /// The item's header has gone under the toolbar, or come back; said only when it changes.
    case headerScrolledAway(Bool, generation: Int)
    /// The page has scrolled, so some of it is under the toolbar; said only when it changes.
    case contentUnderToolbar(Bool, generation: Int)
    /// The item's title took or lost the keyboard.
    case titleFocus(Bool)
    case titleInput(ItemID, String)
    case titleCommit(ItemID, String, startWriting: Bool)
    case titleDiscard(ItemID)
    /// A pin asks for its menu, with the pin's frame in the page's window and the height of that window.
    case headerMenu(PageHeaderMenu, ItemID, CGRect, viewportHeight: Double)
    /// A row of the property block, or Linked From, was opened with the context menu: the row's identifier, as
    /// `PagePlacement` names it, with its frame and the page window's height as for `headerMenu`.
    case propertyMenu(row: String, ItemID, CGRect, viewportHeight: Double)
    case openLink(String)
    /// A link in the item's property block or its linked items was clicked.
    case openItem(ItemID)
    case copy(String)
    case escape
    case pasteImages
    /// A card for an embedded file was clicked.
    case openEmbed(ItemID, EmbedReference)
    /// The context menu is opening over an embedded file, or over anything else when nil, with whether the
    /// app said it may be opened.
    case embedMenu((item: ItemID, reference: EmbedReference, opens: Bool)?)
    /// A `[[link]]` to a note was command-clicked in the note `item`.
    case openNote(ItemID, NoteLink)
    case find(FindState)
    case diagnostic(String)
    case error(String)

    init?(body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "ready":
            self = .ready
        case "changed":
            guard let markdown = dict["markdown"] as? String, let generation = dict["generation"] as? Int else { return nil }
            self = .changed(markdown, generation: generation)
        case "state":
            let marks = (dict["marks"] as? [String] ?? []).compactMap(Mark.init(rawValue:))
            guard let block = Block(dict["block"]) else { return nil }
            self = .state(CaretState(
                marks: Set(marks),
                block: block,
                quoted: dict["quoted"] as? Bool ?? false,
                sourceMode: dict["sourceMode"] as? Bool ?? false,
                inTable: dict["inTable"] as? Bool ?? false,
                canUndo: dict["canUndo"] as? Bool ?? false,
                canRedo: dict["canRedo"] as? Bool ?? false,
                generation: dict["generation"] as? Int ?? -1,
                formats: dict["formats"] as? [String: Bool] ?? [:],
                tables: dict["tables"] as? [String: Bool] ?? [:]
            ))
        case "openLink":
            guard let href = dict["href"] as? String else { return nil }
            self = .openLink(href)
        case "openItem":
            guard let item = dict["item"] as? String, !item.isEmpty else { return nil }
            self = .openItem(ItemID(item))
        case "headerScrolledAway":
            guard let away = dict["away"] as? Bool, let generation = dict["generation"] as? Int else { return nil }
            self = .headerScrolledAway(away, generation: generation)
        case "contentUnderToolbar":
            guard let under = dict["under"] as? Bool, let generation = dict["generation"] as? Int else { return nil }
            self = .contentUnderToolbar(under, generation: generation)
        case "titleFocus":
            guard let focused = dict["focused"] as? Bool else { return nil }
            self = .titleFocus(focused)
        case "titleInput":
            guard let item = dict["item"] as? String, let text = dict["text"] as? String else { return nil }
            self = .titleInput(ItemID(item), text)
        case "titleCommit":
            guard let item = dict["item"] as? String, let text = dict["text"] as? String,
                  let startWriting = dict["startWriting"] as? Bool else { return nil }
            self = .titleCommit(ItemID(item), text, startWriting: startWriting)
        case "titleDiscard":
            guard let item = dict["item"] as? String else { return nil }
            self = .titleDiscard(ItemID(item))
        case "headerMenu":
            guard let item = dict["item"] as? String,
                  let menu = (dict["menu"] as? String).flatMap(PageHeaderMenu.init(rawValue:)),
                  let rect = (dict["rect"] as? [NSNumber])?.map(\.doubleValue), rect.count == 4, rect.allSatisfy(\.isFinite),
                  let viewportHeight = (dict["viewportHeight"] as? NSNumber)?.doubleValue, viewportHeight.isFinite
            else { return nil }
            self = .headerMenu(menu, ItemID(item), CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3]), viewportHeight: viewportHeight)
        case "propertyMenu":
            guard let item = dict["item"] as? String, let row = dict["row"] as? String, !row.isEmpty,
                  let rect = (dict["rect"] as? [NSNumber])?.map(\.doubleValue), rect.count == 4, rect.allSatisfy(\.isFinite),
                  let viewportHeight = (dict["viewportHeight"] as? NSNumber)?.doubleValue, viewportHeight.isFinite
            else { return nil }
            self = .propertyMenu(row: row, ItemID(item), CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3]), viewportHeight: viewportHeight)
        case "copy":
            guard let text = dict["text"] as? String else { return nil }
            self = .copy(text)
        case "escape":
            self = .escape
        case "pasteImages":
            self = .pasteImages
        case "openEmbed":
            guard let (item, reference) = EmbedReference.request(dict["embed"]) else { return nil }
            self = .openEmbed(item, reference)
        case "embedMenu":
            self = .embedMenu(EmbedReference.request(dict["embed"]).map { ($0.item, $0.reference, dict["opens"] as? Bool ?? false) })
        case "openNote":
            guard let item = dict["item"] as? String, !item.isEmpty, let link = NoteLink(page: dict) else { return nil }
            self = .openNote(ItemID(item), link)
        case "find":
            guard let text = dict["text"] as? String,
                  let selection = dict["selection"] as? [Int], selection.count == 2,
                  let visible = dict["visible"] as? [Int], visible.count == 2
            else { return nil }
            self = .find(FindState(
                snapshotID: dict["snapshotId"] as? String ?? "",
                generation: dict["generation"] as? Int ?? -1,
                text: text,
                selection: NSRange(location: selection[0], length: selection[1] - selection[0]),
                visible: NSRange(location: visible[0], length: visible[1] - visible[0]),
                boxes: (dict["boxes"] as? [NSNumber] ?? []).map(\.doubleValue),
                scrollY: (dict["scrollY"] as? NSNumber)?.doubleValue ?? 0,
                viewportHeight: (dict["viewportHeight"] as? NSNumber)?.doubleValue ?? 0
            ))
        case "diagnostic":
            self = .diagnostic(dict["message"] as? String ?? "")
        case "error":
            self = .error(dict["message"] as? String ?? "")
        default:
            return nil
        }
    }
}

extension Block {
    nonisolated init?(_ value: Any?) {
        guard let dict = value as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "paragraph": self = .paragraph
        case "heading":
            guard let level = dict["level"] as? Int else { return nil }
            self = .heading(level)
        case "codeBlock": self = .codeBlock
        case "bulletList": self = .bulletList
        case "orderedList": self = .orderedList
        case "taskList": self = .taskList
        default: return nil
        }
    }
}
