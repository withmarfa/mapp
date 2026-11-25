import CoreGraphics
import Foundation

nonisolated enum Mark: String, Sendable {
    case bold, italic, strikethrough, highlight, code, link
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
    /// The address of the link under the caret, or of the first link in a selection; present exactly when `marks`
    /// holds `.link`.
    var href: String?
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
    /// A loaded item has had its first frame, said once for each load.
    case painted(generation: Int)
    /// The headings of the loaded item in the editor's own order, each with its place in that list, under the load they
    /// belong to. Said after each load and when an edit changes the list. A heading with no words is counted, not listed.
    case headings([OutlineHeading], generation: Int)
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
    /// A property row's or a pin's value asks for its editor under it, with the row's identifier and the value's
    /// frame, as a pin's is.
    case editValue(ItemID, row: String, CGRect, viewportHeight: Double)
    /// A row's or a pin's name was pressed: the row's menu, under the name's frame. `editsValue` is set where the value
    /// holds a link of its own, so the menu is the only way to the value's editor.
    case fieldMenu(ItemID, row: String, editsValue: Bool, CGRect, viewportHeight: Double)
    /// The value an editor was asked for moved on the page, to this frame.
    case valueMoved(ItemID, row: String, CGRect, viewportHeight: Double)
    /// The kicker's type name was pressed: Change Type, under the name's frame.
    case changeType(ItemID, CGRect, viewportHeight: Double)
    /// The page's notice action was chosen, for the item the page shows. Loading pictures is the page's own.
    case noticeAction(ItemID, kind: String)
    case openLink(String)
    /// A link in the item's property block or its linked items was clicked.
    case openItem(ItemID)
    case copy(String)
    case escape
    case pasteImages
    /// A card for an embedded file was clicked.
    case openEmbed(ItemID, EmbedReference)
    /// Quick Look was pressed on the card of an embedded file.
    case quickLookEmbed(ItemID, EmbedReference)
    /// The context menu is opening over an embedded file, or over anything else when nil, with whether the
    /// app said it may be opened.
    case embedMenu((item: ItemID, reference: EmbedReference, opens: Bool)?)
    /// The same menu is opening over a row of the property block, or Linked From, or over none when nil: the row's
    /// identifier as `PagePlacement` names it, and the item the header was showing.
    case rowMenu((item: ItemID, row: String)?)
    /// A row of the property block was dragged: the whole order the page shows after the move, folded rows included.
    case moveRow(ItemID, row: String, order: [String])
    /// A `[[link]]` to an item was command-clicked in the item `item`.
    case openItemLink(ItemID, ItemLink)
    /// The menu of a link in the item's text was asked for, at `point` in the page's window, whose height is
    /// `viewportHeight`, under the load `generation`. Inkkit has selected the link.
    case linkMenu(ItemID, generation: Int, LinkMenuTarget, point: CGPoint, viewportHeight: Double)
    case find(FindState)
    case diagnostic(String)
    /// Text the person typed, pasted or dropped reached a folded section; Inkkit opened it and dropped the input.
    case hiddenText
    case error(String)

    /// The text of a `changed` that did not decode, as when its generation is missing, so it can be handed back.
    static func unreadableChange(_ body: Any) -> String? {
        guard let dict = body as? [String: Any], dict["type"] as? String == "changed" else { return nil }
        return dict["markdown"] as? String
    }

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
                href: dict["href"] as? String,
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
        case "painted":
            guard let generation = dict["generation"] as? Int else { return nil }
            self = .painted(generation: generation)
        case "headings":
            guard let list = dict["headings"] as? [[String: Any]], let generation = dict["generation"] as? Int else { return nil }
            var headings: [OutlineHeading] = []
            for (index, entry) in list.enumerated() {
                guard let level = entry["level"] as? Int, let text = entry["text"] as? String else { return nil }
                let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !words.isEmpty { headings.append(OutlineHeading(level: level, text: words, index: index)) }
            }
            self = .headings(headings, generation: generation)
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
        case "noticeAction":
            guard let item = dict["item"] as? String, let kind = dict["kind"] as? String else { return nil }
            self = .noticeAction(ItemID(item), kind: kind)
        case "changeType":
            guard let item = dict["item"] as? String,
                  let rect = (dict["rect"] as? [NSNumber])?.map(\.doubleValue), rect.count == 4, rect.allSatisfy(\.isFinite),
                  let viewportHeight = (dict["viewportHeight"] as? NSNumber)?.doubleValue, viewportHeight.isFinite
            else { return nil }
            self = .changeType(ItemID(item), CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3]), viewportHeight: viewportHeight)
        case "editValue", "valueMoved", "fieldMenu":
            guard let item = dict["item"] as? String, let row = dict["row"] as? String, !row.isEmpty,
                  let rect = (dict["rect"] as? [NSNumber])?.map(\.doubleValue), rect.count == 4, rect.allSatisfy(\.isFinite),
                  let viewportHeight = (dict["viewportHeight"] as? NSNumber)?.doubleValue, viewportHeight.isFinite
            else { return nil }
            let frame = CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3])
            switch type {
            case "editValue":
                self = .editValue(ItemID(item), row: row, frame, viewportHeight: viewportHeight)
            case "fieldMenu":
                self = .fieldMenu(ItemID(item), row: row, editsValue: dict["editsValue"] as? Bool ?? false, frame, viewportHeight: viewportHeight)
            default:
                self = .valueMoved(ItemID(item), row: row, frame, viewportHeight: viewportHeight)
            }
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
        case "quickLookEmbed":
            guard let (item, reference) = EmbedReference.request(dict["embed"]) else { return nil }
            self = .quickLookEmbed(item, reference)
        case "embedMenu":
            self = .embedMenu(EmbedReference.request(dict["embed"]).map { ($0.item, $0.reference, dict["opens"] as? Bool ?? false) })
        case "rowMenu":
            if let row = dict["row"] as? [String: Any], let item = row["item"] as? String, !item.isEmpty,
               let name = row["row"] as? String, !name.isEmpty {
                self = .rowMenu((ItemID(item), name))
            } else {
                self = .rowMenu(nil)
            }
        case "moveRow":
            guard let item = dict["item"] as? String, !item.isEmpty, let row = dict["row"] as? String, !row.isEmpty,
                  let order = dict["order"] as? [String], order.contains(row)
            else { return nil }
            self = .moveRow(ItemID(item), row: row, order: order)
        case "openItemLink":
            guard let item = dict["item"] as? String, !item.isEmpty, let link = ItemLink(page: dict) else { return nil }
            self = .openItemLink(ItemID(item), link)
        case "linkMenu":
            guard let item = dict["item"] as? String, !item.isEmpty, let generation = dict["generation"] as? Int,
                  let link = dict["link"] as? [String: Any], let target = LinkMenuTarget(page: link),
                  let point = dict["point"] as? [Double], point.count == 2,
                  let viewportHeight = (dict["viewportHeight"] as? NSNumber)?.doubleValue
            else { return nil }
            self = .linkMenu(ItemID(item), generation: generation, target, point: CGPoint(x: point[0], y: point[1]), viewportHeight: viewportHeight)
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
        case "hiddenText":
            self = .hiddenText
        case "error":
            self = .error(dict["message"] as? String ?? "")
        default:
            return nil
        }
    }
}

/// The link a menu is asked for. A web link says whether its address may be opened, which is the page's answer and
/// Inkkit's together; an item link carries what the core reads (`ItemLink`) and the text it shows.
nonisolated enum LinkMenuTarget: Equatable, Sendable {
    case web(text: String, href: String, openable: Bool)
    case item(text: String, ItemLink)

    init?(page dict: [String: Any]) {
        guard let kind = dict["kind"] as? String, let text = dict["text"] as? String else { return nil }
        switch kind {
        case "web":
            guard let href = dict["href"] as? String, let openable = dict["openable"] as? Bool else { return nil }
            self = .web(text: text, href: href, openable: openable)
        case "wiki":
            guard let link = ItemLink(page: dict) else { return nil }
            self = .item(text: text, link)
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
