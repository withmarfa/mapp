import Foundation
import Observation
import UniformTypeIdentifiers

/// A window's new item, in the one line or the text form: the kind of item being made, what the person typed, and
/// where it goes. The draft outlives the panel being put away, a closed window and a quit, since every change is kept
/// on this Mac (`NewItemDrafts`) until the library holds the item. Draft editing and saving stay together so the
/// panel can keep everything the library has yet to take.
@Observable
final class QuickAdd {
    /// How the panel shows the draft: the one line, or the text form, which also takes text and files.
    enum Form: Equatable {
        case line
        case text
    }
    /// A file the person chose, dropped or pasted, read from where it is when the item is added rather than held
    /// in memory. The app may read it for as long as any draft or new item holds it.
    struct File: Equatable, Identifiable {
        let url: URL
        let byteCount: Int64?
        let contentType: UTType?
        private let access: FileAccess

        /// Nil for a folder, a package or anything else that is not one file that can be read. A symbolic link is
        /// taken as the file it points to.
        init?(_ link: URL) {
            access = FileAccess(link)
            let url = link.resolvingSymlinksInPath()
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey]),
                  values.isRegularFile == true, FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false))
            else { return nil }
            self.url = url
            byteCount = values.fileSize.map(Int64.init)
            contentType = values.contentType
        }

        var id: URL { url }
        var name: String { url.lastPathComponent }
        /// Whether the file is still where it was taken from, since it is read only when the item is added.
        var isOnDisk: Bool { FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)) }

        static func == (lhs: File, rhs: File) -> Bool { lhs.url == rhs.url }

        /// The files' names in a sentence: “a.pdf” and “b.png”.
        static func names(_ files: [File]) -> String {
            files.map { "“\($0.name)”" }.formatted(.list(type: .and))
        }

        /// Tells the person which files could not be read as a file, such as a folder, and how many things given
        /// were not files at all. Says nothing where there are none.
        static func tellUnreadable(_ names: [String], unreadable: Int = 0, to notices: Notices) {
            if !names.isEmpty {
                notices.tell(
                    String(localized: "Can’t Add File"),
                    String(localized: "The app can’t read \(names.formatted(.list(type: .and))) as a file."))
            }
            if unreadable > 0 {
                notices.tell(String(localized: "Can’t Add File"), AttributedString(localized: "^[\(unreadable) item](inflect: true) can’t be added as a file.").text)
            }
        }

        /// The sentence that tells the person these files were not added.
        static func notAdded(_ files: [File]) -> String {
            files.count == 1
                ? String(localized: "\(names(files)) wasn’t added.")
                : String(localized: "\(names(files)) weren’t added.")
        }
    }

    /// Holds the security scope of a file the person chose in a panel, which `fileImporter` gives sandboxed or not, so
    /// the file can be read later, and gives it up once nothing holds the file.
    nonisolated final class FileAccess: Sendable {
        private let url: URL
        private let scoped: Bool

        init(_ url: URL) {
            self.url = url
            scoped = url.startAccessingSecurityScopedResource()
        }

        deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
    }

    /// A detail of the item the panel shows as a chip: its parent, one of its kind's fields, or, on the line, a tag.
    enum Chip: Hashable {
        case parent
        case field(String)
        case tag(String)
    }

    /// A word typed on the line that a chip chosen for it stands for, as `@lis` for the parent chosen while it was
    /// typed. The word stays in the title, which Add takes out where it then stands.
    struct Mark: Equatable {
        /// Where the word stands in the title, in characters, moved with each edit before it.
        var range: Range<Int>
        let words: String
        let chip: Chip
    }

    struct Draft: Equatable {
        var typeID: String
        var title = ""
        var body = ""
        /// How many characters of the body come before the caret, so the page can put it back there.
        var caret: Int?
        var properties: [String: PropertyValue] = [:]
        /// The values the kind gave the draft before anything was typed (`QuickAdd.prefill`), which are not the
        /// person's work: they leave with the kind that gave them, and alone they are not worth keeping.
        var prefilled: [String: PropertyValue] = [:]
        /// Whether the person took away a value the kind gave, so a later kind gives none.
        var declinedPrefill = false
        var parentID: ItemID?
        /// The chips the person added, in the order they were added, whether or not they hold a value yet. A
        /// required field is always shown, so it is not listed here.
        var chips: [Chip] = []
        /// For a file, the file; for any other kind, the files attached to the item once it is made.
        var files: [File] = []
        /// The tags the item is made with, in the order given.
        var tags: [String] = []
        /// Where the item goes: the Library, or the Feed. It starts as the place the panel opened in says
        /// (`QuickAdd.startingTier`), and the In row changes it.
        var tier: Tier = .library
        /// The words on the line that chips chosen for them stand for (`QuickAdd.Mark`).
        var marks: [Mark] = []
        /// Words the person told the line not to read, by Delete on their chip, which stay text.
        var declined: [String] = []
        /// Values typed for fields the kind now lacks, by key, kept and not sent, which come back when the kind
        /// changes to one that has the field.
        var setAside: [String: PropertyValue] = [:]
        /// A parent the kind now cannot have, kept and not sent, which comes back for a kind that can.
        var setAsideParent: ItemID?

        /// The values the person set or changed: every one but a value the kind gave and nobody touched.
        var typedProperties: [String: PropertyValue] {
            properties.filter { $0.value != .null && prefilled[$0.key] != $0.value }
        }

        /// Whether the person put anything in it worth keeping: text, a file, a parent, a value, a tag or a chip they
        /// added.
        var hasContent: Bool {
            !NameText.trimmed(title).isEmpty || !isBlank(body) || !files.isEmpty || parentID != nil
                || !typedProperties.isEmpty || !chips.isEmpty || !tags.isEmpty || !setAside.isEmpty || setAsideParent != nil
        }

        /// What the clipboard is given when the draft cannot be added: the title, then the body, then the values and
        /// the parent, named. Without a library, the values go by their keys and the parent by its ID.
        func text(in library: (any ItemLibrary)?) -> String? {
            var details: [String] = []
            if let library {
                let typed = typedProperties
                for field in QuickAdd.fields(of: typeID, in: library.catalogue) {
                    guard let value = typed[field.key] else { continue }
                    details.append("\(field.label): \(QuickAdd.valueText(value, in: field))")
                }
                if let parentID {
                    details.append("\(String(localized: "Parent")): \(library.item(parentID)?.displayTitle ?? String(localized: "Item not found"))")
                }
            } else {
                for (key, value) in typedProperties.sorted(by: { $0.key < $1.key }) {
                    details.append("\(key): \(ItemValueText.string(value))")
                }
                if let parentID { details.append("\(String(localized: "Parent")): \(parentID.rawValue)") }
            }
            if !tags.isEmpty { details.append(tags.map { "#" + $0 }.joined(separator: " ")) }
            let parts = [NameText.trimmed(title), isBlank(body) ? "" : body, details.joined(separator: "\n")].filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
        }

        /// Where the page puts the caret, or nil where no body was typed.
        var pageCaret: PageCaret? {
            isBlank(body) ? nil : PageCaret(offset: caret, in: body)
        }

        private func isBlank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        /// Shows a chip, after the ones already shown.
        mutating func add(_ chip: Chip) {
            if !chips.contains(chip) { chips.append(chip) }
        }

        /// Puts the item under `parent` and shows the chip for it.
        mutating func setParent(_ parent: ItemID) {
            parentID = parent
            add(.parent)
        }

        /// Takes a chip away with the value it holds. A required field stays, since the item cannot be added
        /// without it.
        mutating func remove(_ chip: Chip, in catalogue: Catalogue) {
            guard QuickAdd.isRemovable(chip, typeID: typeID, in: catalogue) else { return }
            takeOut(chip)
        }

        /// Gives the item a tag and shows its chip, after the ones already shown.
        mutating func addTag(_ tag: String) {
            if !tags.contains(tag) { tags.append(tag) }
            add(.tag(tag))
        }

        /// Takes a chip and its value out. A word on the line it stood for stays, as text the line no longer reads.
        private mutating func takeOut(_ chip: Chip) {
            chips.removeAll { $0 == chip }
            for mark in marks where mark.chip == chip && !declined.contains(mark.words) { declined.append(mark.words) }
            marks.removeAll { $0.chip == chip }
            switch chip {
            case .parent: parentID = nil
            case .field(let key):
                properties[key] = nil
                if prefilled[key] != nil { declinedPrefill = true }
                prefilled[key] = nil
            case .tag(let tag): tags.removeAll { $0 == tag }
            }
        }

        /// Delete on a chip of the line: a chip read from words stops being read, and a chosen one goes, unless it
        /// holds a value the person set in its panel. Every word typed stays in the title. Returns whether it changed
        /// anything.
        @discardableResult
        mutating func decline(_ chip: Chip, readFrom words: [String]) -> Bool {
            var changed = false
            for phrase in words where !declined.contains(phrase) {
                declined.append(phrase)
                changed = true
            }
            let chosen = switch chip {
            case .parent: parentID != nil
            case .field(let key): chips.contains(chip) && typedProperties[key] == nil
            case .tag(let tag): tags.contains(tag)
            }
            if chosen {
                takeOut(chip)
                changed = true
            }
            return changed
        }

        /// Moves each mark with an edit of the title from `old`: one before the edit stays, one after it moves with
        /// it, and one the edit reached, or joined to without a space, is gone, so its words are text again.
        mutating func followMarks(from old: String) {
            guard !marks.isEmpty, old != title else { return }
            let before = Array(old)
            let after = Array(title)
            var prefix = 0
            while prefix < before.count, prefix < after.count, before[prefix] == after[prefix] { prefix += 1 }
            var suffix = 0
            while suffix < before.count - prefix, suffix < after.count - prefix,
                  before[before.count - 1 - suffix] == after[after.count - 1 - suffix] { suffix += 1 }
            let editEnd = before.count - suffix
            let shift = after.count - before.count
            let inserted = after[prefix..<(after.count - suffix)]
            marks = marks.compactMap { mark in
                if mark.range.upperBound < prefix || (mark.range.upperBound == prefix && inserted.first?.isWhitespace != false) {
                    return mark
                }
                guard mark.range.lowerBound > editEnd || (mark.range.lowerBound == editEnd && inserted.last?.isWhitespace != false)
                else { return nil }
                var moved = mark
                moved.range = (mark.range.lowerBound + shift)..<(mark.range.upperBound + shift)
                return moved
            }
        }

        /// Whether the draft still holds the chip a mark stands for, in `catalogue`'s fields for its kind.
        func holds(_ chip: Chip, in catalogue: Catalogue) -> Bool {
            switch chip {
            case .parent: parentID != nil
            case .field(let key): chips.contains(chip) && QuickAdd.fields(of: typeID, in: catalogue).contains { $0.key == key }
            case .tag(let tag): tags.contains(tag)
            }
        }
    }

    var draft: Draft? {
        didSet { keep() }
    }
    var isPresented = false
    var form = Form.line
    /// Where the draft is kept, which a test replaces with its own.
    @ObservationIgnored var drafts = NewItemDrafts.standard()
    /// The draft's place among the kept drafts, while this window holds one.
    @ObservationIgnored private(set) var entry: UUID?
    /// The words of an Added line, or the reason a refused draft came back, which a panel with no toast shows under
    /// the line.
    var lastAdded: String?
    /// The Undo of the last Added line, while it is still the undo manager's latest step.
    var lastUndo: StepUndo?
    /// The draft came back after the app quit while it was being added, so it may be in Marfa already and its Add
    /// asks first (`asksAgain`).
    var mayBeInMarfa = false
    /// Whether the window asks the person to add again a draft that may be in Marfa already.
    var asksAgain = false
    /// What the line and the text form say of a draft that may be in Marfa already.
    static var mayBeInMarfaNotice: String {
        String(localized: "This may already be in Marfa. The app quit while it was being added, so check the library before you add it again.")
    }

    /// Writes the draft as it now is, or drops it where it is empty.
    private func keep() {
        guard let entry, let draft else { return }
        let kept = drafts.update(entry, draft)
        guard kept != entry else { return }
        // The draft was on its way, so it waits in the store as sent and the window goes on in a new one.
        self.entry = kept
    }

    /// Starts this window's draft in `library`: the one a closed window or an earlier run left there, else a new one
    /// made by `make`. Answers whether a kept draft came back.
    @discardableResult
    func begin(in library: any ItemLibrary, make: () -> Draft?) -> Bool {
        drafts.notices = library.notices
        // A draft added in an earlier run that the library refused is offered again first.
        drafts.settle(in: library)
        if let kept = drafts.take(.line, in: library.serverKey) {
            entry = kept.id
            draft = kept.draft
            cameBack(kept, in: library)
            if !kept.missingFiles.isEmpty {
                library.notices.tell(
                    String(localized: "File Not Found"),
                    String(localized: "\(kept.missingFiles.map { "“\($0)”" }.formatted(.list(type: .and))) is no longer where it was, so it was taken out of the new item."))
            }
            return true
        }
        guard let made = make() else { return false }
        entry = drafts.make(.line, made, in: library.serverKey)
        draft = made
        mayBeInMarfa = false
        return false
    }

    /// Says why a kept draft came back, and marks one that may be in Marfa already.
    private func cameBack(_ kept: NewItemDrafts.Entry, in library: any ItemLibrary) {
        mayBeInMarfa = kept.interrupted
        if kept.interrupted {
            lastAdded = Self.mayBeInMarfaNotice
        } else if kept.returned {
            lastAdded = String(localized: "The item wasn’t added. What you typed is back.")
        }
    }

    /// Takes the draft `id` another holder let go, as the line over another app hands its draft to a window's text
    /// form. An empty draft this window held is let go first. Answers whether it was taken.
    func take(_ id: UUID, in library: any ItemLibrary) -> Bool {
        guard !holdsContent, let kept = drafts.take(id, in: library.serverKey) else { return false }
        if let entry { drafts.drop(entry) }
        drafts.notices = library.notices
        entry = kept.id
        draft = kept.draft
        mayBeInMarfa = kept.interrupted
        listDrafts = [:]
        return true
    }

    /// Takes back a draft the library refused, where this window holds nothing typed, and says why it came back.
    func takeBackRefused(in library: any ItemLibrary) {
        drafts.settle(in: library)
        guard !holdsContent, let kept = drafts.takeReturned(.line, in: library.serverKey) else { return }
        if let entry { drafts.drop(entry) }
        entry = kept.id
        draft = kept.draft
        cameBack(kept, in: library)
    }
    /// The work on each list field's entries, by key: an entry being added, or a member's text not yet in the draft.
    /// Kept here, not by the popover that edits it, so closing the popover keeps it. Observed, so the panel's word on
    /// an unfinished entry and its Add button follow it.
    var listDrafts: [String: ItemPropertyDraft] = [:]

    /// The work on the entries of list field `key`, made on first use. Make it before a view reads it, as the popover
    /// opens, since making it changes what the panel observes.
    func listDraft(for key: String) -> ItemPropertyDraft {
        if let draft = listDrafts[key] { return draft }
        let draft = ItemPropertyDraft()
        listDrafts[key] = draft
        return draft
    }

    /// The list fields holding text not yet in the draft, which holds the draft back until it is finished or removed.
    var unfinishedLists: [ItemTypeInfo.Field] {
        listDrafts.sorted { $0.key < $1.key }.compactMap { $0.value.holdsUnsavedList ? $0.value.field : nil }
    }

    /// The text of each list field not yet in the draft, named, for the clipboard.
    private var unfinishedListText: [String] {
        listDrafts.sorted { $0.key < $1.key }.compactMap { _, draft in
            guard let field = draft.field, case .list(let shape) = field.kind, let text = draft.list.unsavedText(in: shape) else { return nil }
            return "\(field.label): \(text)"
        }
    }

    /// Ends the draft once it is added (`NewItemDrafts.added`) or cleared.
    func clearDraft() {
        if let entry { drafts.escape(entry) }
        entry.map(drafts.release)
        entry = nil
        draft = nil
        mayBeInMarfa = false
        listDrafts = [:]
    }

    /// The draft was added as `item`: it stays kept until the library holds the item, and the window starts afresh.
    fileprivate func added(as item: ItemID) {
        if let entry { drafts.added(entry, as: item) }
        entry = nil
        draft = nil
        mayBeInMarfa = false
        listDrafts = [:]
    }

    /// Whether the draft, or a list field's entries, hold anything worth keeping.
    var holdsContent: Bool { draft?.hasContent == true || !unfinishedLists.isEmpty }
    /// The draft as it was when its file was sent, while the file is being added, so the panel does not add it
    /// twice and a closing window does not hand off what is already on its way.
    private var sending: Draft?
    /// The kept draft whose file is on its way, which the window may let go before the library answers.
    private var sendingEntry: UUID?
    /// The window let go of what it held while the file was on its way.
    private var leftWhileSending = false
    /// While the core is asked about the parent, before anything is sent. The draft is still the window's to hand
    /// off, since nothing is on its way, so this only stops a second Add.
    private var checkingParent = false
    var isSaving: Bool { sending != nil || checkingParent }

    /// Why a draft leaves the window before it is added.
    enum Departure {
        /// The window closed, or the app quit.
        case closed
        /// The window went on to another library, whose items and fields the draft's place and properties do not name.
        case libraryChanged
    }

    init() { Self.open.add(self) }

    /// Every window's new item, so a quit can hand over what no draft holds.
    private static let open = NSHashTable<QuickAdd>.weakObjects()

    /// Lets every window's draft go as the app quits (`leave`).
    static func leaveAll(telling notices: Notices) {
        for quickAdd in open.allObjects { quickAdd.leave(because: .closed, telling: notices) }
    }

    /// Lets the draft go as it leaves the window. The draft stays kept on this Mac (`NewItemDrafts`), and the next
    /// window to open a new item in its library takes it back. A draft whose file is on its way stays kept as it was
    /// sent until the library answers (`fileSent`), and only what was typed after it, less what was sent, is offered
    /// meanwhile. An entry
    /// still being typed into a list field is in no draft, so that alone goes to the clipboard through `notices`,
    /// which tells the person.
    func leave(because departure: Departure, telling notices: Notices) {
        let lists = unfinishedListText
        if let entry, var rest = draft, let sending, sendingEntry != nil, !leftWhileSending {
            rest.files.removeAll { sending.files.contains($0) }
            if NameText.trimmed(rest.title) == NameText.trimmed(sending.title) { rest.title = "" }
            if rest.parentID == sending.parentID { rest.parentID = nil }
            rest.properties = rest.properties.filter { sending.properties[$0.key] != $0.value }
            rest.chips.removeAll { sending.chips.contains($0) }
            rest.tags.removeAll { sending.tags.contains($0) }
            drafts.release(drafts.update(entry, rest))
        } else if let entry {
            drafts.release(entry)
        }
        if sendingEntry != nil { leftWhileSending = true }
        entry = nil
        draft = nil
        mayBeInMarfa = false
        asksAgain = false
        listDrafts = [:]
        isPresented = false
        guard !lists.isEmpty else { return }
        let reason = switch departure {
        case .closed: String(localized: "The window closed before the entry was added to the new item.")
        case .libraryChanged: String(localized: "The window changed to another library before the entry was added to the new item.")
        }
        notices.notKept(String(localized: "Entry Not Added"), text: lists.joined(separator: "\n"), reason: reason)
    }

    /// The file is about to be sent, marked so first (`NewItemDrafts.sendingFile`). False where the mark is kept
    /// nowhere, so nothing is sent.
    fileprivate func saving(_ draft: Draft) -> Bool {
        guard let entry, drafts.sendingFile(entry) else { return false }
        sending = draft
        sendingEntry = entry
        return true
    }

    /// Returns whether the window still holds the draft. Where the window closed, or went on in a new draft, the
    /// draft as sent is kept until Marfa answers the queued create, or, if queuing failed, given back and the person
    /// told where to find it.
    fileprivate func fileSent(_ item: ItemID?, telling notices: Notices) -> Bool {
        let files = Array(sending?.files.prefix(1) ?? [])
        sending = nil
        let held = !leftWhileSending
        leftWhileSending = false
        guard let sent = sendingEntry else { return true }
        sendingEntry = nil
        guard sent != entry else { return true }
        if let item {
            drafts.added(sent, as: item)
        } else {
            drafts.giveBack(sent)
            notices.tell(
                String(localized: "File Not Added"),
                String(localized: "\(QuickAdd.File.names(files)) wasn’t added, so what you typed for it is kept. It comes back the next time you make a new item."))
        }
        return held
    }
    /// The create about to be made from the draft, kept first (`NewItemDrafts.sending`). False where the draft is kept
    /// nowhere, so nothing would follow the create.
    fileprivate func willCreate(_ item: ItemID) -> Bool {
        guard let entry else { return false }
        return drafts.sending(entry, as: item)
    }
    /// The library made nothing, so the draft stays as typed.
    fileprivate func notCreated() {
        if let entry { drafts.notSent(entry) }
    }
    fileprivate func checking(parent: Bool) { checkingParent = parent }

    /// Tells the person what an added draft held for fields or a parent its kind lacks, which was not sent, with it
    /// on the clipboard.
    static func tellSetAside(_ draft: Draft, in library: any ItemLibrary) {
        var lines: [String] = []
        let fields = library.catalogue.itemTypes.values.flatMap(\.fields)
        for (key, value) in draft.setAside.sorted(by: { $0.key < $1.key }) {
            let field = fields.first { $0.key == key }
            lines.append("\(field?.label ?? key): \(field.map { valueText(value, in: $0) } ?? ItemValueText.string(value))")
        }
        if let parent = draft.setAsideParent {
            lines.append("\(String(localized: "Parent")): \(library.item(parent)?.displayTitle ?? parent.rawValue)")
        }
        guard !lines.isEmpty else { return }
        library.notices.notKept(
            String(localized: "Not Added to the Item"), text: lines.joined(separator: "\n"),
            reason: String(localized: "The kind of item added can’t hold these, so they were left out."))
    }

    // MARK: What is remembered

    /// Where an item made in `place` goes until the In row says otherwise: the Feed in the Feed, else the Library.
    static func startingTier(in place: Place) -> Tier {
        place == .feed ? .feed : .library
    }

    /// The sidebar's types in its order, groups opened.
    static func typeIDs(of nodes: [TypeNode]) -> [TypeID] {
        nodes.flatMap { node in (node.type.map { [$0] } ?? []) + typeIDs(of: node.children) }
    }

    // MARK: Kinds and fields

    /// Whether New Item can open the panel: the library is read and offers a kind to make.
    static func isAvailable(in library: any ItemLibrary) -> Bool {
        // A draft is kept for one instance, so none is begun before the library knows which it reads.
        guard library.isLoaded, !library.serverKey.isEmpty else { return false }
        let catalogue = library.catalogue
        return catalogue.itemTypes[.file] != nil || catalogue.itemTypes.keys.contains(where: catalogue.isCreatable)
    }

    /// The kinds of item the panel offers, by label, with File after them where the catalogue has files.
    static func types(in library: any ItemLibrary) -> [ItemTypeOption] {
        let catalogue = library.catalogue
        var types = library.creatableTypes
        if catalogue.itemTypes[.file] != nil {
            types.append(ItemTypeOption(id: .file, label: catalogue.label(for: .file), icon: catalogue.icon(for: .file)))
        }
        return types
    }

    /// Keeps the chosen kind above the divider even if the sidebar does not show it.
    static func kindMenu(_ types: [ItemTypeOption], shown: [TypeID], chosen: String?) -> (first: [ItemTypeOption], rest: [ItemTypeOption]) {
        var first = shown.filter { $0 != .file }.compactMap { id in types.first { $0.id == id } }
        if first.isEmpty, let note = types.first(where: { $0.id == TypeID("core.note") }) { first.append(note) }
        if let file = types.first(where: { $0.id == .file }) { first.append(file) }
        if let chosen, let option = types.first(where: { $0.id.rawValue == chosen }), !first.contains(option) {
            first.append(option)
        }
        let rest = types.filter { !first.contains($0) }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        return (first, rest)
    }

    /// The fields the panel offers for a kind: those the person can set, not its title or text. A file has none,
    /// since a file is added from its URL and the library takes no values with it.
    static func fields(of typeID: String, in catalogue: Catalogue) -> [ItemTypeInfo.Field] {
        guard !isFile(typeID, in: catalogue), let info = catalogue.itemTypes[TypeID(typeID)] else { return [] }
        return info.fields.filter { field in
            guard field.key != info.titleKey, field.key != info.bodyKey else { return false }
            return !field.kind.isOutsideForms
        }
    }

    /// What a new item of the kind holds before anything is typed. Marfa's types declare no defaults, so this is only
    /// what a declaration says: the status field takes the first word the type puts in the not-started group, the
    /// word a board's move into that group writes. A type with no such word, or no status field, gives nothing, and
    /// no other field is filled.
    static func prefill(of typeID: String, in catalogue: Catalogue) -> [String: PropertyValue] {
        guard let field = fields(of: typeID, in: catalogue).first(where: \.isStatus),
              case .status(let words) = field.kind,
              let word = words.first(where: { $0.group == .notStarted })
        else { return [:] }
        return [field.key: .string(word.value)]
    }

    /// The required fields of the kind that the new-item forms cannot set, since they are an object or a list of words, which
    /// only the item's own value panel edits. The panel says so; the library refuses the item without them and tells
    /// the person, so Add is never held back here.
    static func unsettableRequired(of typeID: String, in catalogue: Catalogue) -> [ItemTypeInfo.Field] {
        guard !isFile(typeID, in: catalogue), let info = catalogue.itemTypes[TypeID(typeID)] else { return [] }
        return info.fields.filter { $0.required && $0.kind.isOutsideForms && $0.key != info.titleKey && $0.key != info.bodyKey }
    }

    /// What the panel says under the title for a kind with such fields, before anything is typed. Add stays on: the
    /// library refuses the create (`MarfaEngine.creationProperties`) and tells the person, so the note says that first.
    static func unsettableNote(_ fields: [ItemTypeInfo.Field]) -> String? {
        guard !fields.isEmpty else { return nil }
        let names = fields.map(\.label).formatted(.list(type: .and))
        return String(localized: "Adding will be refused: this kind of item needs \(names), which the app can’t fill in. Choose another kind.")
    }

    /// The kind the new item opens in: the one asked for, else the one a type's own place holds, else the one Settings >
    /// General > New Items names (`chosen`), else the last used, then a note, then any. A kind not in `offered` (a type
    /// since deleted, or one nobody can make) is passed over. A type's place is its list, and the Collections index's a
    /// collection.
    static func startingType(
        asked: String?, place: PlaceView, chosen: String? = nil, remembered: String?, offered: [String], in catalogue: Catalogue
    ) -> String? {
        func choice(_ id: String?) -> String? { id.flatMap { offered.contains($0) ? $0 : nil } }
        let held: String? = switch place.place {
        case .type(let type) where place.view == .own: type.rawValue
        case .collections: offered.first { catalogue.isCollection(TypeID($0)) }
        default: nil
        }
        return choice(asked) ?? choice(held) ?? choice(chosen) ?? choice(remembered) ?? choice("core.note") ?? offered.first
    }

    /// The chips the panel shows for a draft: the kind's required fields first, then what the person added in the
    /// order added, then any value or parent the draft holds that was not added by hand. A field the kind does
    /// not have is never shown.
    static func shownChips(_ draft: Draft, in catalogue: Catalogue) -> [Chip] {
        let fields = fields(of: draft.typeID, in: catalogue)
        let keys = Set(fields.map(\.key))
        var shown = fields.filter(\.required).map { Chip.field($0.key) }
        for chip in draft.chips where !shown.contains(chip) {
            switch chip {
            case .parent: if draft.parentID != nil { shown.append(chip) }
            case .field(let key): if keys.contains(key) { shown.append(chip) }
            case .tag: break
            }
        }
        if draft.parentID != nil, !shown.contains(.parent) { shown.append(.parent) }
        for field in fields where draft.properties[field.key].map({ $0 != .null }) == true && !shown.contains(.field(field.key)) {
            shown.append(.field(field.key))
        }
        return shown
    }

    /// What the add menu lists besides attaching a file: the parent, where the kind can have one and the draft
    /// has none, then the kind's fields that are not shown, in the catalogue's order.
    static func offeredChips(_ draft: Draft, in catalogue: Catalogue, canHaveParent: Bool) -> [Chip] {
        let shown = shownChips(draft, in: catalogue)
        var offered: [Chip] = []
        if canHaveParent, !shown.contains(.parent) { offered.append(.parent) }
        offered += fields(of: draft.typeID, in: catalogue).map { Chip.field($0.key) }.filter { !shown.contains($0) }
        return offered
    }

    /// Whether the person can take a chip away: all but a required field.
    static func isRemovable(_ chip: Chip, typeID: String, in catalogue: Catalogue) -> Bool {
        switch chip {
        case .parent, .tag: true
        case .field(let key): fields(of: typeID, in: catalogue).first { $0.key == key }?.required != true
        }
    }

    /// Whether the kind keeps text, so the panel offers a body.
    static func hasBody(_ typeID: String, in catalogue: Catalogue) -> Bool {
        catalogue.itemTypes[TypeID(typeID)]?.bodyKey != nil
    }

    static func isFile(_ typeID: String, in catalogue: Catalogue) -> Bool {
        catalogue.isFileType(TypeID(typeID))
    }

    /// Whether the draft holds text its kind does not keep, as when a text item's text stays after the kind changes to
    /// a file. The text stays in sight and holds the draft back until it is removed or the kind changes back, so
    /// none is dropped.
    static func holdsTextItCannotKeep(_ draft: Draft, in catalogue: Catalogue) -> Bool {
        let keepsText = !isFile(draft.typeID, in: catalogue) && hasBody(draft.typeID, in: catalogue)
        return !keepsText && !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether the panel shows the text: for a kind that keeps it, or while it holds text the kind cannot keep.
    static func showsBody(_ draft: Draft, in catalogue: Catalogue) -> Bool {
        (!isFile(draft.typeID, in: catalogue) && hasBody(draft.typeID, in: catalogue))
            || holdsTextItCannotKeep(draft, in: catalogue)
    }

    /// Whether a file draft holds more than the one file a file item keeps, as when a text item's attachments stay
    /// after the kind changes to File. The files stay in sight and hold the draft back until all but one are
    /// removed or the kind changes back.
    static func holdsFilesItCannotKeep(_ draft: Draft, in catalogue: Catalogue) -> Bool {
        isFile(draft.typeID, in: catalogue) && draft.files.count > 1
    }

    /// A value as its chip shows it: a choice by its label, a Boolean as Yes or No, anything else as written.
    static func valueText(_ value: PropertyValue, in field: ItemTypeInfo.Field) -> String {
        if field.kind == .boolean, case .bool(let flag) = value { return flag ? String(localized: "Yes") : String(localized: "No") }
        if case .list(let shape) = field.kind { return shape.display(of: value) }
        if field.isPicked, let option = value.string { return ItemTypeInfo.Field.label(ofOption: option) }
        return ItemValueText.string(value)
    }

    /// Whether the draft names a parent the library no longer holds. The chip says so and can be removed, and the
    /// draft is not added while it stays, so a parent the library does not hold is never sent.
    static func holdsMissingParent(_ draft: Draft, in library: any ItemLibrary) -> Bool {
        draft.parentID.map { library.item($0) == nil } ?? false
    }

    /// Whether the draft can be added: a title, or one file for a file, a value for every required field, no text
    /// its kind cannot keep, and no parent the library lacks. A kind whose title Marfa does not require, such as a
    /// bookmark, may go without one where the draft holds text or a value of the person's.
    static func canSave(_ draft: Draft, in library: any ItemLibrary) -> Bool {
        let catalogue = library.catalogue
        if holdsMissingParent(draft, in: library) || holdsTextItCannotKeep(draft, in: catalogue) { return false }
        if isFile(draft.typeID, in: catalogue) { return draft.files.count == 1 }
        let holdsMore = !draft.typedProperties.isEmpty || !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !NameText.trimmed(draft.title).isEmpty || (!titleRequired(draft.typeID, in: catalogue) && holdsMore) else { return false }
        return fields(of: draft.typeID, in: catalogue).allSatisfy { field in
            !field.required || draft.properties[field.key].map { $0 != .null } == true
        }
    }
}

extension Browser {
    /// Opens a new item: the one line or the text form, as Settings > General > New Opens says unless `form` is given,
    /// with `kind` chosen where one is given and `title` typed where the draft is new. This is every New's one way in,
    /// the search's "New Item" among them. A draft put away, or kept from a closed window or an earlier run, comes
    /// back as it was left, its title untouched, since the person's own draft wins. Otherwise the kind is the place's
    /// own type (`QuickAdd.startingType`), then the one last added here, then a note, and the item goes where the
    /// place says (`QuickAdd.startingTier`). A kind the line cannot make whole (`QuickAdd.lineOffers`) opens the
    /// text form.
    func openNewItem(kind: String? = nil, title: String = "", form: QuickAdd.Form? = nil, in library: any ItemLibrary) {
        // A draft is kept for one instance, so none is begun before the library knows which it reads.
        guard QuickAdd.isAvailable(in: library) else { return }
        let interval = Telemetry.begin(.navigation, "quickAdd.open")
        defer { interval.end() }
        palette = nil
        quickAdd.lastAdded = nil
        let types = QuickAdd.types(in: library).map(\.id.rawValue)
        let recent = NewItemRecents.stored(for: library.serverKey, in: defaults).kinds.first
        if quickAdd.draft == nil {
            let tier = QuickAdd.startingTier(in: shown.place)
            let restored = quickAdd.begin(in: library) {
                guard let start = QuickAdd.startingType(
                    asked: kind, place: shown, chosen: NewItemType.stored(in: defaults), remembered: recent, offered: types,
                    in: library.catalogue)
                else { return nil }
                var draft = QuickAdd.Draft(typeID: start)
                draft.tier = tier
                return draft
            }
            guard quickAdd.draft != nil else { return }
            if restored {
                if let kind, types.contains(kind) { chooseQuickAddType(kind, in: library) }
            } else {
                chooseQuickAddType(quickAdd.draft?.typeID ?? "", in: library)
                let words = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !words.isEmpty { quickAdd.draft?.title = words }
            }
        } else if let kind, types.contains(kind) {
            chooseQuickAddType(kind, in: library)
        }
        let chosen = form ?? (NewOpens.stored(in: defaults) == .line ? .line : .text)
        let fits = quickAdd.draft.map { QuickAdd.lineOffers($0.typeID, in: library.catalogue) } ?? true
        quickAdd.form = chosen == .line && fits ? .line : .text
        quickAdd.isPresented = true
    }

    /// Opens the draft `id` another holder let go in this window's text form, where this window holds nothing typed.
    /// Answers whether it did.
    func openHandedNewItem(_ id: UUID, in library: any ItemLibrary) -> Bool {
        guard quickAdd.take(id, in: library) else { return false }
        openNewItem(form: .text, in: library)
        return true
    }

    /// Moves the draft from the line to the text form, as Add Text does, with everything typed. The text form reads
    /// no words, so what the line read leaves the title for its tokens, as at Add (`QuickAdd.finishLine`).
    func handOverToTextForm(in library: any ItemLibrary, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) {
        if quickAdd.form == .line, var draft = quickAdd.draft {
            QuickAdd.finishLine(&draft, in: library, now: now, calendar: calendar, locale: locale)
            if draft != quickAdd.draft { quickAdd.draft = draft }
        }
        quickAdd.form = .text
        quickAdd.lastAdded = nil
    }

    /// Changes the kind of item, keeping what was typed and the files given. A value or parent the new kind cannot
    /// take is set aside in the draft, not sent, and comes back when the kind changes to one that can; an Add that
    /// leaves it behind says so (`QuickAdd.tellSetAside`).
    func chooseQuickAddType(_ typeID: String, in library: any ItemLibrary) {
        guard var draft = quickAdd.draft else { return }
        draft.typeID = typeID
        let keys = Set(QuickAdd.fields(of: typeID, in: library.catalogue).map(\.key))
        // What the last kind gave goes with it, unless the person changed it; then the new kind gives its own.
        for (key, value) in draft.prefilled where draft.properties[key] == value { draft.properties[key] = nil }
        for (key, value) in draft.properties where !keys.contains(key) && value != .null { draft.setAside[key] = value }
        draft.properties = draft.properties.filter { keys.contains($0.key) }
        for (key, value) in draft.setAside where keys.contains(key) && draft.properties[key] == nil {
            draft.properties[key] = value
            draft.add(.field(key))
            draft.setAside[key] = nil
        }
        draft.prefilled = draft.declinedPrefill
            ? [:] : QuickAdd.prefill(of: typeID, in: library.catalogue).filter { draft.properties[$0.key] == nil }
        draft.properties.merge(draft.prefilled) { current, _ in current }
        if let parent = draft.parentID, !library.admitsCreationParent(parent, typeID: typeID) {
            draft.setAsideParent = parent
            draft.parentID = nil
        } else if draft.parentID == nil, let parent = draft.setAsideParent, library.admitsCreationParent(parent, typeID: typeID) {
            draft.setParent(parent)
            draft.setAsideParent = nil
        }
        draft.chips = draft.chips.filter { chip in
            switch chip {
            case .parent: draft.parentID != nil
            case .field(let key): keys.contains(key)
            case .tag(let tag): draft.tags.contains(tag)
            }
        }
        // A list field the new kind lacks gives back any entry still being typed into it.
        for (key, list) in quickAdd.listDrafts where !keys.contains(key) {
            if let field = list.field, case .list(let shape) = field.kind, let text = list.list.unsavedText(in: shape) {
                library.notices.notKept(
                    String(localized: "Property Not Saved"), text: "\(field.label): \(text)",
                    reason: String(localized: "The new kind of item doesn’t have this property."))
            }
            quickAdd.listDrafts[key] = nil
        }
        quickAdd.draft = draft
    }

    /// Puts the new item away without adding anything; the draft waits for the panel to come back.
    func putAwayQuickAdd() {
        quickAdd.isPresented = false
        if quickAdd.draft != nil, !quickAdd.holdsContent { quickAdd.clearDraft() }
    }

    /// Puts an empty new item away once its window has stopped being the one in front, as a menu closes when the
    /// person moves on. A draft with anything in it stays, since the person meant to come back to it. Nothing the
    /// panel opens itself counts as leaving: its file importer and popovers (`usesOwnSurface`), and any other
    /// window it opened, such as a sheet or a popover's window (`keyWindowIsOwn`), take the key for a moment.
    /// Returns whether it put the panel away.
    @discardableResult
    func putAwayQuickAddLeftEmpty(usesOwnSurface: Bool, keyWindowIsOwn: Bool) -> Bool {
        guard quickAdd.isPresented, quickAdd.draft != nil, !quickAdd.holdsContent, !usesOwnSurface, !keyWindowIsOwn else { return false }
        putAwayQuickAdd()
        return true
    }

    /// Adds the draft as an item of its kind, with its properties, tags and tier, in one create, then links its parent.
    /// With `opening`, the panel closes and the window opens the item the way Settings says (`ItemOpening`), adds it
    /// to the collection being shown, and attaches the draft's files to it (`finishNewItems`). Without it, as the line's
    /// Add, the panel stays open, empty, with the same kind, and the window only adds the item to the collection. The
    /// draft stays kept until the library holds the item (`NewItemDrafts.added`), so one the library refuses comes
    /// back. Where the library cannot make it, everything stays as typed and the library tells the person why. The
    /// core is asked about the parent first: a second Add does nothing meanwhile, a window that closes meanwhile keeps
    /// the whole draft, and a draft changed meanwhile stays as typed and is not added, and the person is told to add
    /// it again. A file no longer where it was is taken out of the draft and named, and nothing is added until the
    /// person has seen that. Nothing empty is ever written. `toasts` hears the line's Added, with an Undo that takes
    /// back the add alone. A draft that may be in Marfa already (`QuickAdd.mayBeInMarfa`) is added only `again`.
    @discardableResult
    func saveQuickAdd(
        in library: any ItemLibrary, undoManager: UndoManager?, opening: Bool = true, toasts: ToastPresenter? = nil,
        again: Bool = false, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current
    ) async -> ItemID? {
        // The line's words stay as typed until the item is made; only what is sent has the read words taken out.
        guard let typed = quickAdd.draft else { return nil }
        var draft = typed
        if quickAdd.form == .line {
            QuickAdd.finishLine(&draft, in: library, now: now, calendar: calendar, locale: locale)
            // A required value the line has no place for is asked for by the text form, with everything typed.
            if !QuickAdd.missingRequired(draft, in: library.catalogue).isEmpty {
                handOverToTextForm(in: library, now: now, calendar: calendar, locale: locale)
                return nil
            }
        }
        guard !quickAdd.isSaving, QuickAdd.canSave(draft, in: library), quickAdd.unfinishedLists.isEmpty else { return nil }
        // A draft back from a quit mid-add may be in Marfa already, so it is added again only once the person says so.
        if quickAdd.mayBeInMarfa {
            guard again else {
                quickAdd.asksAgain = true
                return nil
            }
            quickAdd.mayBeInMarfa = false
        }
        let missing = draft.files.filter { !$0.isOnDisk }
        guard missing.isEmpty else {
            quickAdd.draft?.files.removeAll { missing.contains($0) }
            let names = QuickAdd.File.names(missing)
            if missing.count == 1 {
                library.notices.tell(
                    String(localized: "File Not Found"),
                    String(localized: "\(names) is no longer where it was, so it was taken out of the new item. Add it again, or add the item without it."))
            } else {
                library.notices.tell(
                    String(localized: "Files Not Found"),
                    String(localized: "\(names) are no longer where they were, so they were taken out of the new item. Add them again, or add the item without them."))
            }
            return nil
        }
        // Before anything is made, so a parent the core refuses leaves no item behind. A second Add does nothing
        // meanwhile. Nothing is on its way yet, so a window that closes or changes library meanwhile still keeps the
        // whole draft, and the draft no longer matching below stops the create.
        if let parent = draft.parentID {
            quickAdd.checking(parent: true)
            let verdict = await library.newChildVerdict(under: parent)
            quickAdd.checking(parent: false)
            // Text typed while the core was asked stays as typed; nothing is made from the draft as it was. A draft
            // that left the window is kept already.
            guard quickAdd.draft == typed else {
                if quickAdd.draft != nil {
                    library.notices.tell(
                        String(localized: "Item Not Added"),
                        String(localized: "The new item changed while its parent was being checked, so nothing was added. Add it again."))
                }
                return nil
            }
            if case .refused(let reason) = verdict {
                library.notices.tell(String(localized: "Can’t Create Item"), reason)
                return nil
            }
        }
        let interval = Telemetry.begin(.navigation, "quickAdd.save")
        defer { interval.end() }
        let catalogue = library.catalogue
        let isFile = QuickAdd.isFile(draft.typeID, in: catalogue)
        var startsGroup = undoManager?.groupingLevel == 0
        let id: ItemID?
        if isFile, let file = draft.files.first {
            guard quickAdd.saving(typed) else {
                library.notices.tell(
                    String(localized: "Item Not Added"),
                    String(localized: "The app couldn’t save the new item on this Mac before sending it, so nothing was added. What you typed is still there. Try again."))
                return nil
            }
            let title = NameText.trimmed(draft.title)
            id = await library.addFile(
                file.url, title: title.isEmpty ? nil : title, parentID: draft.parentID, tier: draft.tier, tags: draft.tags)
            let held = quickAdd.fileSent(id, telling: library.notices)
            guard let id else {
                if held { quickAdd.notCreated() }
                return nil
            }
            // The file is a step of its own, as a created item is, so the toast's Undo takes back this file.
            startsGroup = undoManager?.groupingLevel == 0
            let opensGroup = startsGroup && undoManager?.groupsByEvent == false
            if opensGroup { undoManager?.beginUndoGrouping() }
            library.registerNewItemUndo(id, undoManager: undoManager)
            if opensGroup { undoManager?.endUndoGrouping() }
            // The person may have changed the draft while the file was sent; only the file sent is taken from it.
            guard held, quickAdd.draft == typed else {
                if held {
                    quickAdd.notCreated()
                    quickAdd.draft?.files.removeAll { $0 == file }
                }
                return id
            }
        } else {
            // Kept as sent before it is made, so a crash or a held-up write never makes it twice.
            let made = ItemID.mint(at: now)
            guard quickAdd.willCreate(made) else {
                library.notices.tell(
                    String(localized: "Item Not Added"),
                    String(localized: "The app couldn’t save the new item on this Mac before sending it, so nothing was added. What you typed is still there. Try again."))
                return nil
            }
            let opensGroup = startsGroup && undoManager?.groupsByEvent == false
            if opensGroup { undoManager?.beginUndoGrouping() }
            id = library.createItem(
                as: made, typeID: draft.typeID, title: draft.title, body: draft.body,
                properties: draft.properties.filter { $0.value != .null }, tags: draft.tags, parentID: draft.parentID,
                tier: draft.tier, undoManager: undoManager)
            if opensGroup { undoManager?.endUndoGrouping() }
            if id == nil { quickAdd.notCreated() }
        }
        guard let id else { return nil }
        // This add's own step, which the create or the file registered just now in a group of its own, and never
        // whatever was on top before it.
        let step = startsGroup ? undoManager.map { StepUndo(undoManager: $0) } : nil
        QuickAdd.tellSetAside(draft, in: library)
        NewItemRecents.remember(kind: draft.typeID, tags: draft.tags, parent: draft.parentID, for: library.serverKey, in: defaults)
        quickAdd.added(as: id)
        let keepsText = !isFile && QuickAdd.hasBody(draft.typeID, in: catalogue)
        var collection: ItemID?
        if shown.view == .own, case .collection(let id) = shown.place { collection = id }
        let entry = NewItem(
            id: id, typeID: draft.typeID, library: library, caret: keepsText ? draft.pageCaret : nil, isFile: isFile,
            attachments: isFile ? [] : draft.files, embedsInText: keepsText, collection: collection,
            opening: opening ? ItemOpening.stored(in: defaults) : nil)
        newItems.append(entry)
        if opening {
            quickAdd.isPresented = false
        } else {
            // The line stays for the next item, of the same kind and going to the same place.
            let restored = quickAdd.begin(in: library) {
                var next = QuickAdd.Draft(typeID: draft.typeID)
                next.tier = draft.tier
                return next
            }
            if !restored { chooseQuickAddType(draft.typeID, in: library) }
            let name = NameText.trimmed(draft.title).isEmpty ? catalogue.label(for: TypeID(draft.typeID)) : NameText.trimmed(draft.title)
            let words = String(localized: "Added “\(name)”")
            if let toasts {
                var undo: (@MainActor () -> Void)?
                if let step { undo = { step.perform() } }
                let shown = toasts.show(words, symbol: "checkmark.circle", undo: undo)
                step?.onLapse = { [weak toasts] in toasts?.dismiss(ifShowing: shown) }
            } else {
                // A panel with no toast, as over another app, says it on its own line.
                quickAdd.lastAdded = words
                quickAdd.lastUndo = step
                step?.onLapse = { [weak quickAdd] in quickAdd?.lastUndo = nil }
            }
        }
        finishNewItems(in: library)
        return id
    }
}
