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
    var inTable = false
    var canUndo = false
    var canRedo = false
}

/// What the page tells the app, decoded from the JSON it posts to the `host` message handler.
nonisolated enum EditorMessage: Sendable {
    case ready
    case changed(String, generation: Int)
    case state(CaretState)
    case scrolled(CGFloat, generation: Int)
    case openLink(String)
    case copy(String)
    case escape
    case pasteImages
    case find(FindState)
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
                inTable: dict["inTable"] as? Bool ?? false,
                canUndo: dict["canUndo"] as? Bool ?? false,
                canRedo: dict["canRedo"] as? Bool ?? false
            ))
        case "openLink":
            guard let href = dict["href"] as? String else { return nil }
            self = .openLink(href)
        case "scrolled":
            guard let offset = dict["offset"] as? Double, offset.isFinite,
                  let generation = dict["generation"] as? Int else { return nil }
            self = .scrolled(offset, generation: generation)
        case "copy":
            guard let text = dict["text"] as? String else { return nil }
            self = .copy(text)
        case "escape":
            self = .escape
        case "pasteImages":
            self = .pasteImages
        case "find":
            guard let text = dict["text"] as? String,
                  let selection = dict["selection"] as? [Int], selection.count == 2,
                  let visible = dict["visible"] as? [Int], visible.count == 2
            else { return nil }
            self = .find(FindState(
                text: text,
                selection: NSRange(location: selection[0], length: selection[1] - selection[0]),
                visible: NSRange(location: visible[0], length: visible[1] - visible[0]),
                boxes: (dict["boxes"] as? [NSNumber] ?? []).map(\.doubleValue),
                scrollY: (dict["scrollY"] as? NSNumber)?.doubleValue ?? 0,
                viewportHeight: (dict["viewportHeight"] as? NSNumber)?.doubleValue ?? 0
            ))
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
