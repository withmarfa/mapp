import MarfaIcons
import SwiftUI
import UniformTypeIdentifiers

/// ⌘N and every New, unless Settings > General > New Opens says Text Form: one line that makes an item. The kind is
/// the capsule at its start, which Tab moves on; `#` adds a tag, `@` a parent and `/` a property of the kind, each
/// from a list of matches in its row under the line; a day typed is the item's due or start date; a pasted web address
/// makes a bookmark. What the line reads leaves the words for a chip after them, in the order made, and Delete puts
/// the words back. Return adds it and leaves the line open, empty, with the same kind; ⌘Return adds it and opens it;
/// ⇧Return hands everything typed to the text form. Escape or a click outside puts it away, keeping what was typed
/// (`NewItemDrafts`).
///
/// The window shows it over its content, with the window's toast; over another app it stands in a panel of its own
/// (`NewItemAnywhere`), with an Added message and Undo in the panel.
struct NewItemLinePanel: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @Environment(\.undoManager) private var windowUndo
    @Environment(\.colorScheme) private var scheme
    let browser: Browser
    @Bindable var quickAdd: QuickAdd
    /// The window's toast, or nil over another app.
    var toasts: ToastPresenter?
    /// The panel's own undo manager, over another app, where no window gives one.
    var undoManager: UndoManager?
    /// What Add and Open does over another app, where the line's own browser has no window to open the item in.
    var opensElsewhere: ((ItemID, String) -> Void)?
    let onClose: () -> Void

    /// What has the keyboard: the title, or a chip the person chose, which Delete puts back into the title.
    private enum LineFocus: Hashable {
        case title
        case chip(QuickAdd.Chip)
    }

    @FocusState private var focus: LineFocus?
    @State private var titleSelection: TextSelection?
    /// How wide the title's words are, so the chips stand right after them.
    @State private var titleWidth: CGFloat = 0
    /// The match the arrow keys are on.
    @State private var highlighted = 0
    /// The property, by key, whose value panel is open.
    @State private var editing: String?
    @State private var isChoosingFile = false
    @State private var isDropTargeted = false

    var body: some View {
        if let draft = quickAdd.draft {
            content(draft)
        }
    }

    private var undo: UndoManager? { undoManager ?? windowUndo }

    private func content(_ draft: QuickAdd.Draft) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldRow(draft)
            keyRows(draft)
                .padding(.leading, 18)
                .padding(.trailing, 8)
                .padding(.bottom, 8)
            if let lastAdded = quickAdd.lastAdded {
                addedLine(lastAdded)
            }
            foot(draft)
                .frame(height: 32)
                .padding(.leading, 18)
                .padding(.trailing, 10)
                .padding(.bottom, 10)
        }
        .floatingPanelSurface(width: 680, cornerRadius: 22)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in take(providers) }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { take([url]) }
        }
        .onKeyPress(.escape) {
            putAway()
            return .handled
        }
        .onWindowResignsKey { keyWindowIsOwn in
            if browser.putAwayQuickAddLeftEmpty(usesOwnSurface: isChoosingFile || editing != nil, keyWindowIsOwn: keyWindowIsOwn) { onClose() }
        }
        .task {
            // Asked any sooner, the field is not yet in the window and the list keeps the keyboard.
            try? await Task.sleep(for: .milliseconds(50))
            focus = .title
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New Item")
        .accessibilityIdentifier("NewItemLine")
    }

    // MARK: The line

    /// The kind, then the title, then a chip for each part the line read or the person chose, in the order made.
    private func fieldRow(_ draft: QuickAdd.Draft) -> some View {
        let catalogue = library.catalogue
        let chips = QuickAdd.lineChips(draft, in: catalogue)
        let isFile = QuickAdd.isFile(draft.typeID, in: catalogue)
        return HStack(spacing: 12) {
            kindPill(draft)
            TagFlowLayout(spacing: 7) {
                titleField(draft, fills: chips.isEmpty && !isFile)
                ForEach(chips, id: \.self) { chip in lineChip(chip, in: draft) }
                if isFile { fileToken(draft) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .contentShape(.rect)
            .onTapGesture { focus = .title }
        }
        .padding(.leading, 12)
        .padding(.trailing, 18)
        .padding(.top, 4)
        .frame(minHeight: 62)
    }

    /// The kind, as a tinted capsule whose menu lists the kinds the line can make: the sidebar's and File, then the
    /// rest after a divider (`QuickAdd.kindMenu`).
    private func kindPill(_ draft: QuickAdd.Draft) -> some View {
        let menu = lineKindMenu(draft)
        let chosen = (menu.first + menu.rest).first { $0.id.rawValue == draft.typeID }
        let label = chosen?.label ?? library.catalogue.label(for: TypeID(draft.typeID))
        return Menu {
            Picker("Kind", selection: Binding { draft.typeID } set: { browser.chooseQuickAddType($0, in: library) }) {
                ForEach(menu.first) { type in kindLabel(type).tag(type.id.rawValue) }
                if !menu.rest.isEmpty {
                    Divider()
                    ForEach(menu.rest) { type in kindLabel(type).tag(type.id.rawValue) }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            TintedChip(text: label, icon: library.catalogue.icon(for: TypeID(draft.typeID)), isPill: true)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .fixedSize()
        .help("Kind of Item")
        .accessibilityLabel("Kind of Item")
        .accessibilityValue(label)
        .accessibilityIdentifier("NewItemLineKind")
    }

    private func kindLabel(_ type: ItemTypeOption) -> some View {
        Label(type.label, typeIcon: library.catalogue.icon(for: type.id))
    }

    /// The title, as wide as its words so the chips stand after them, or the whole line while there are none.
    private func titleField(_ draft: QuickAdd.Draft, fills: Bool) -> some View {
        let placeholder = QuickAdd.linePlaceholder(draft, in: library.catalogue)
        let width = titleWidth + 6
        return TextField(placeholder, text: Binding {
            quickAdd.draft?.title ?? ""
        } set: { text in
            let old = quickAdd.draft?.title ?? ""
            quickAdd.draft?.title = text
            browser.lineTextChanged(from: old, in: library)
            highlighted = 0
        }, selection: $titleSelection)
        .textFieldStyle(.plain)
        .interfaceFont(.title3)
        .frame(minWidth: 1, idealWidth: fills ? 560 : width, maxWidth: fills ? .infinity : width, minHeight: 26)
        .background(alignment: .leading) {
            // The words as the field draws them, measured for its width.
            Text(verbatim: draft.title.isEmpty ? placeholder : draft.title)
                .interfaceFont(.title3)
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { titleWidth = $0 }
        }
        .focused($focus, equals: .title)
        .onSubmit { returnPressed(shift: false) }
        .onKeyPress(keys: [.return]) { press in
            guard press.modifiers.contains(.shift) else { return .ignored }
            returnPressed(shift: true)
            return .handled
        }
        .onKeyPress(keys: [.tab, KeyEquivalent("\u{19}")]) { press in
            cycleKind(backward: press.modifiers.contains(.shift) || press.key == KeyEquivalent("\u{19}"))
        }
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard let count = matches(for: draft)?.count, count > 0 else { return .ignored }
            highlighted = (highlighted + (press.key == .upArrow ? count - 1 : 1)) % count
            return .handled
        }
        .onKeyPress(.delete) {
            guard caretIsAtStart(of: draft.title) else { return .ignored }
            return putBack(nil) ? .handled : .ignored
        }
        .accessibilityIdentifier("NewItemLineTitle")
    }

    /// Whether the caret stands before the first character with nothing selected, where Delete takes the last chip.
    private func caretIsAtStart(of title: String) -> Bool {
        if title.isEmpty { return true }
        guard case .selection(let range)? = titleSelection?.indices else { return false }
        return range.isEmpty && range.lowerBound == title.startIndex
    }

    /// One chip of the line: what it sets in secondary, its value in primary. Delete, or Keep as Text in its menu,
    /// puts the words it was read from back into the title; a property's chip opens its value panel when clicked.
    @ViewBuilder
    private func lineChip(_ chip: QuickAdd.Chip, in draft: QuickAdd.Draft) -> some View {
        let words = QuickAdd.lineChipWords(chip, in: draft, library: library, calendar: .current, locale: .current)
        let source = draft.sources[chip]
        let chipView = LineChip(name: words.name, value: words.value, isChosen: focus == .chip(chip))
            .focusable()
            .focused($focus, equals: .chip(chip))
            .focusEffectDisabled()
            .onKeyPress(keys: [.delete, .deleteForward]) { _ in
                putBack(chip)
                return .handled
            }
            .onTapGesture {
                focus = .chip(chip)
                if case .field(let key) = chip { editing = key }
            }
            .contextMenu {
                if let source {
                    Button("Keep “\(source.words)” as Text") { putBack(chip) }
                } else if QuickAdd.isRemovable(chip, typeID: draft.typeID, in: library.catalogue) {
                    Button("Remove") {
                        if editing.map({ chip == .field($0) }) == true { editing = nil }
                        quickAdd.draft?.remove(chip, in: library.catalogue)
                        focus = .title
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(words.value.map { "\(words.name) \($0)" } ?? words.name)
            .accessibilityAction(named: source.map { "Keep “\($0.words)” as Text" } ?? String(localized: "Remove")) { putBack(chip) }
        if case .field(let key) = chip, let field = QuickAdd.fields(of: draft.typeID, in: library.catalogue).first(where: { $0.key == key }) {
            chipView
                .popover(isPresented: Binding { editing == key } set: { if !$0, editing == key { editing = nil } }, arrowEdge: .bottom) {
                    ItemPropertyRow(definition: field, value: draft.properties[key], isEditable: true, onChange: { newValue in
                        quickAdd.draft?.properties[key] = newValue
                        // A value set by hand is no longer the words it was read from.
                        quickAdd.draft?.sources[chip] = nil
                        return true
                    }, retainedDraft: field.kind.isList ? quickAdd.listDraft(for: key) : nil, startsEditing: true,
                       handsOffOnLeave: !field.kind.isList)
                    .padding(14)
                    .frame(width: 340)
                }
                .accessibilityIdentifier("NewItemLineProperty.\(key)")
        } else {
            chipView
        }
    }

    /// Takes a chip out, or the last one where none is named, and gives the title the keyboard, its caret at the end.
    @discardableResult
    private func putBack(_ chip: QuickAdd.Chip?) -> Bool {
        if let chip, case .field(let key) = chip, editing == key { editing = nil }
        guard browser.putBackLineChip(chip, in: library) else { return false }
        focus = .title
        if let title = quickAdd.draft?.title { titleSelection = TextSelection(insertionPoint: title.endIndex) }
        return true
    }

    /// A file item's file: the one chosen, or a button to choose one, which a drop on the panel also gives.
    private func fileToken(_ draft: QuickAdd.Draft) -> some View {
        Group {
            if let file = draft.files.first {
                LineChip(name: String(localized: "File"), value: file.name, isChosen: false)
                    .contextMenu {
                        Button("Remove “\(file.name)”") { quickAdd.draft?.files = [] }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(file.name)
                    .accessibilityAction(named: String(localized: "Remove")) { quickAdd.draft?.files = [] }
            } else {
                HStack(spacing: 6) {
                    Button("Choose a File…") { isChoosingFile = true }
                        .appButton(.secondary, size: .small)
                        .accessibilityIdentifier("NewItemLineChooseFile")
                    Text("or drop one here")
                        .foregroundStyle(.tertiary)
                }
                .frame(minHeight: 26)
            }
        }
    }

    // MARK: Rows under the line

    /// A row for each key the line reads: its key, what it sets, and offers from this library, the recent first. While
    /// nothing is typed, the first row offers kinds; while a key's word is typed, its row lists the matches instead.
    private func keyRows(_ draft: QuickAdd.Draft) -> some View {
        let typing = NewItemText.typing(in: draft.title)
        let matches = matches(for: draft)
        let recents = NewItemRecents.stored(for: library.serverKey, in: browser.defaults)
        let canHaveParent = library.canHaveParent(typeID: draft.typeID)
        return VStack(alignment: .leading, spacing: 0) {
            if !draft.hasContent {
                keyRow("Kind", key: "Tab") { kindOffers(draft, recents: recents) }
            }
            keyRow("Tag", key: "#") {
                if typing?.mark == .tag, let matches { matchList(matches, query: typing?.query ?? "") } else { tagOffers(draft, recents: recents) }
            }
            if canHaveParent {
                keyRow("Parent", key: "@") {
                    if typing?.mark == .parent, let matches {
                        matchList(matches, query: typing?.query ?? "")
                    } else {
                        parentOffers(draft, recents: recents)
                    }
                }
            }
            keyRow("Property", key: "/") {
                if typing?.mark == .property, let matches {
                    matchList(matches, query: typing?.query ?? "")
                } else {
                    propertyOffers(draft)
                }
            }
        }
    }

    private func keyRow<Offers: View>(_ title: LocalizedStringKey, key: String, @ViewBuilder offers: () -> Offers) -> some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(spacing: 0) {
                KeyCap(key: key)
                    .frame(width: 38, alignment: .leading)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 100, height: 34, alignment: .leading)
            offers()
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        }
    }

    /// The kinds, the last used first, then as the kind menu orders them, with the rest under More.
    private func kindOffers(_ draft: QuickAdd.Draft, recents: NewItemRecents) -> some View {
        let menu = lineKindMenu(draft)
        let kinds = QuickAdd.kindOffers(menu.first + menu.rest, recents: recents.kinds, chosen: draft.typeID, shown: 6)
        return HStack(spacing: 2) {
            ForEach(kinds.offered) { type in
                offer(type.label, mark: .type(library.catalogue.icon(for: type.id)), isOn: type.id.rawValue == draft.typeID) {
                    browser.chooseLineMatch(.kind(type.id.rawValue), in: library)
                }
            }
            if !kinds.more.isEmpty {
                moreOffers {
                    ForEach(kinds.more) { type in
                        Button { browser.chooseLineMatch(.kind(type.id.rawValue), in: library) } label: { kindLabel(type) }
                    }
                }
            }
        }
    }

    private func tagOffers(_ draft: QuickAdd.Draft, recents: NewItemRecents) -> some View {
        let tags = QuickAdd.tagOffers("", draft: draft, recents: recents.tags, in: library).known.prefix(5)
        return HStack(spacing: 2) {
            ForEach(Array(tags), id: \.self) { tag in
                offer(tag, mark: .tag, isOn: false) { browser.chooseLineMatch(.tag(tag), in: library) }
            }
        }
    }

    private func parentOffers(_ draft: QuickAdd.Draft, recents: NewItemRecents) -> some View {
        let parents = draft.parentID == nil
            ? library.creationParentMatches(typeID: draft.typeID, matching: "", first: recents.parents, limit: 3, newest: true) : []
        return HStack(spacing: 2) {
            ForEach(parents) { item in
                offer(item.displayTitle, mark: .type(library.catalogue.icon(for: item.type)), isOn: false) {
                    browser.chooseLineMatch(.parent(item.id), in: library)
                }
            }
        }
    }

    private func propertyOffers(_ draft: QuickAdd.Draft) -> some View {
        let fields = offeredFields(draft, query: "")
        return HStack(spacing: 2) {
            ForEach(fields.prefix(4), id: \.key) { field in
                offer(field.label, mark: nil, isOn: false) { chooseField(field.key) }
            }
            if fields.count > 4 {
                moreOffers {
                    ForEach(fields.dropFirst(4), id: \.key) { field in
                        Button(field.label) { chooseField(field.key) }
                    }
                }
            }
        }
    }

    private enum OfferMark {
        case type(String?)
        case tag
    }

    /// One offer under the line, as a quiet capsule; the one in use stands on the gray wash.
    private func offer(_ text: String, mark: OfferMark?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                switch mark {
                case .type(let icon): TypeGlyph(id: icon).font(.system(size: 12))
                case .tag: Text(verbatim: "#").foregroundStyle(.tertiary)
                case nil: EmptyView()
                }
                Text(verbatim: text).lineLimit(1)
            }
            .font(.system(size: 12, weight: isOn ? .medium : .regular))
            .foregroundStyle(isOn ? .primary : .secondary)
            .padding(.leading, 8)
            .padding(.trailing, 9)
            .frame(height: 26)
            .background(isOn ? ChipLooks.current.chipWash(for: scheme) : .clear, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    /// More, at the end of a row: the rest of what the row offers, in a menu.
    private func moreOffers<Items: View>(@ViewBuilder items: () -> Items) -> some View {
        Menu {
            items()
        } label: {
            HStack(spacing: 5) {
                Text("More")
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.leading, 8)
            .padding(.trailing, 9)
            .frame(height: 26)
            .contentShape(.capsule)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
    }

    /// One match for the marked word being typed.
    private struct Match: Identifiable {
        let id: String
        let text: String
        let mark: OfferMark
        let detail: String?
        let choice: Browser.LineChoice?
        let field: String?
    }

    /// The matches for the marked word at the end of the line, or nil while none is being typed.
    private func matches(for draft: QuickAdd.Draft) -> [Match]? {
        guard let typing = NewItemText.typing(in: draft.title) else { return nil }
        let query = typing.query
        switch typing.mark {
        case .tag:
            let recents = NewItemRecents.stored(for: library.serverKey, in: browser.defaults).tags
            let offer = QuickAdd.tagOffers(query, draft: draft, recents: recents, in: library)
            var found = offer.known.map { Match(id: "tag:" + $0, text: $0, mark: .tag, detail: nil, choice: .tag($0), field: nil) }
            if let new = offer.new {
                found.append(Match(id: "new:" + new, text: new, mark: .tag, detail: String(localized: "New Tag"), choice: .tag(new), field: nil))
            }
            return found
        case .parent:
            guard library.canHaveParent(typeID: draft.typeID) else { return [] }
            let recents = NewItemRecents.stored(for: library.serverKey, in: browser.defaults).parents
            return library.creationParentMatches(typeID: draft.typeID, matching: query, first: recents, limit: 6, newest: false).map { item in
                Match(
                    id: "parent:" + item.id.rawValue, text: item.displayTitle, mark: .type(library.catalogue.icon(for: item.type)),
                    detail: library.catalogue.label(for: item.type), choice: .parent(item.id), field: nil)
            }
        case .property:
            return offeredFields(draft, query: query).map { field in
                Match(id: "field:" + field.key, text: field.label, mark: .type(nil), detail: nil, choice: nil, field: field.key)
            }
        }
    }

    /// Return takes the highlighted match.
    private func matchList(_ matches: [Match], query: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if matches.isEmpty {
                Text("No Matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .frame(height: 34)
            }
            ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                Button { choose(match) } label: {
                    HStack(spacing: 8) {
                        Group {
                            switch match.mark {
                            case .type(let icon?): TypeGlyph(id: icon)
                            case .type(nil): EmptyView()
                            case .tag: Text(verbatim: "#").foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 14)
                        Text(Self.bold(query, in: match.text))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                        if let detail = match.detail {
                            Text(verbatim: detail)
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 10)
                    .frame(height: 32)
                    .background(index == highlighted ? ChipLooks.current.chipWash(for: scheme) : .clear, in: .rect(cornerRadius: 9))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("NewItemLineMatch")
            }
        }
        .padding(.vertical, 1)
    }

    /// `text` with every place it holds `query` in bold, as the palette shows what was typed.
    private static func bold(_ query: String, in text: String) -> AttributedString {
        var out = AttributedString()
        for run in NewItemText.matchRuns(of: query, in: text) {
            var piece = AttributedString(run.text)
            if run.matches { piece.inlinePresentationIntent = .stronglyEmphasized }
            out += piece
        }
        return out
    }

    private func choose(_ match: Match) {
        if let choice = match.choice {
            browser.chooseLineMatch(choice, in: library)
        } else if let key = match.field {
            chooseField(key)
        }
        highlighted = 0
        focus = .title
    }

    private func chooseField(_ key: String) {
        browser.chooseLineMatch(.field(key), in: library)
        Task { editing = key }
    }

    /// The kind's fields the person can still add as a chip, matching `query`.
    private func offeredFields(_ draft: QuickAdd.Draft, query: String) -> [ItemTypeInfo.Field] {
        let fields = QuickAdd.fields(of: draft.typeID, in: library.catalogue)
        let shown = Set(QuickAdd.lineChips(draft, in: library.catalogue))
        return fields.filter { field in
            !shown.contains(.field(field.key)) && (query.isEmpty || field.label.localizedStandardContains(query))
        }
    }

    /// What the line added, where no toast says it: over another app.
    private func addedLine(_ words: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
            Text(verbatim: words)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let step = quickAdd.lastUndo {
                Button("Undo") {
                    step.perform()
                    quickAdd.lastUndo = nil
                    quickAdd.lastAdded = nil
                }
                .appButton(.plain, size: .small)
                .accessibilityIdentifier("NewItemLineUndo")
            }
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 30)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("NewItemLineAdded")
    }

    // MARK: The foot

    /// Where the item goes, as a quiet pop-up; Add Text; and, once the line can add, Add and Add and Open in one capsule.
    private func foot(_ draft: QuickAdd.Draft) -> some View {
        let canAdd = QuickAdd.canSave(lineFinished(draft), in: library) && !quickAdd.isSaving
            || !QuickAdd.missingRequired(draft, in: library.catalogue).isEmpty
        return HStack(spacing: 14) {
            wherePicker(draft)
            Spacer(minLength: 0)
            Button {
                browser.handOverToTextForm()
            } label: {
                HStack(spacing: 8) {
                    Text("Add Text")
                    ShortcutKeys("⇧↩").accessibilityHidden(true)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("NewItemLineAddText")
            if canAdd {
                SegmentCapsule(fontSize: 13, weight: .medium) {
                    Button {
                        add(opening: false)
                    } label: {
                        HStack(spacing: 8) {
                            Text("Add")
                            ShortcutKeys("↩").accessibilityHidden(true)
                        }
                    }
                    .accessibilityIdentifier("NewItemLineAdd")
                    Divider()
                        .frame(height: 14)
                    Button {
                        add(opening: true)
                    } label: {
                        HStack(spacing: 8) {
                            Text("Add and Open")
                            ShortcutKeys("⌘↩").accessibilityHidden(true)
                        }
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityIdentifier("NewItemLineAddAndOpen")
                }
            }
        }
    }

    /// In, then the place's mark and name, as a pop-up that chooses the Library or the Feed.
    private func wherePicker(_ draft: QuickAdd.Draft) -> some View {
        let place: SidebarPlace = draft.tier == .feed ? .feed : .library
        let name = library.name(of: draft.tier == .feed ? .feed : .library)
        return HStack(spacing: 6) {
            Text("In")
                .foregroundStyle(.tertiary)
            Menu {
                Picker("In", selection: Binding { draft.tier } set: { quickAdd.draft?.tier = $0 }) {
                    Label(library.name(of: .library), systemImage: SidebarPlace.library.symbol ?? "").tag(Tier.library)
                    Label(library.name(of: .feed), systemImage: SidebarPlace.feed.symbol ?? "").tag(Tier.feed)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack(spacing: 6) {
                    if let symbol = place.symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Text(verbatim: name)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel("In")
            .accessibilityValue(name)
            .accessibilityIdentifier("NewItemLineIn")
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }

    /// The draft as Add would send it, so the buttons are on only when it can be added.
    private func lineFinished(_ draft: QuickAdd.Draft) -> QuickAdd.Draft {
        var finished = draft
        QuickAdd.finishLine(&finished, in: library, now: .now, calendar: .current, locale: .current)
        return finished
    }

    // MARK: Actions

    private func returnPressed(shift: Bool) {
        if shift {
            browser.handOverToTextForm()
            return
        }
        if let draft = quickAdd.draft, let matches = matches(for: draft), !matches.isEmpty {
            choose(matches[min(highlighted, matches.count - 1)])
            return
        }
        add(opening: false)
        focus = .title
    }

    private func add(opening: Bool) {
        let typeID = quickAdd.draft?.typeID ?? ""
        Task {
            if opening, let opensElsewhere {
                guard let id = await browser.saveQuickAdd(in: library, undoManager: undo, opening: false, toasts: toasts) else { return }
                opensElsewhere(id, typeID)
            } else {
                _ = await browser.saveQuickAdd(in: library, undoManager: undo, opening: opening, toasts: toasts)
                if opening, !quickAdd.isPresented { onClose() }
            }
        }
    }

    /// Tab and Shift-Tab move the kind through those the line can make.
    private func cycleKind(backward: Bool) -> KeyPress.Result {
        guard let draft = quickAdd.draft else { return .ignored }
        let kinds = lineKinds(draft)
        guard let index = kinds.firstIndex(where: { $0.id.rawValue == draft.typeID }), kinds.count > 1 else { return .ignored }
        let next = (index + (backward ? kinds.count - 1 : 1)) % kinds.count
        browser.chooseQuickAddType(kinds[next].id.rawValue, in: library)
        return .handled
    }

    private func lineKinds(_ draft: QuickAdd.Draft) -> [ItemTypeOption] {
        let menu = lineKindMenu(draft)
        return menu.first + menu.rest
    }

    private func lineKindMenu(_ draft: QuickAdd.Draft) -> (first: [ItemTypeOption], rest: [ItemTypeOption]) {
        let shown = QuickAdd.typeIDs(of: SidebarPlan(library, layout: libraries.sidebarLayout).shownTypes)
        return QuickAdd.lineKindMenu(QuickAdd.types(in: library), shown: shown, chosen: draft.typeID, in: library.catalogue)
    }

    private func putAway() {
        browser.putAwayQuickAdd()
        onClose()
    }

    private func take(_ providers: [NSItemProvider]) -> Bool {
        let providers = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !providers.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let url = await FileIntake.fileURL(of: provider) { urls.append(url) }
            }
            take(urls)
        }
        return true
    }

    /// A file dropped on the line is a file item's file, or, for any other kind, hands the draft to the text form,
    /// which attaches files.
    private func take(_ urls: [URL]) {
        var taken: [QuickAdd.File] = []
        var unreadable: [String] = []
        for url in urls {
            if let file = QuickAdd.File(url) { taken.append(file) } else { unreadable.append("“\(url.lastPathComponent)”") }
        }
        QuickAdd.File.tellUnreadable(unreadable, to: library.notices)
        guard let draft = quickAdd.draft, !taken.isEmpty else { return }
        if QuickAdd.isFile(draft.typeID, in: library.catalogue) {
            // A file item holds one file; the text form says so where more were given.
            quickAdd.draft?.files = taken
            if taken.count > 1 { browser.handOverToTextForm() }
        } else {
            quickAdd.draft?.files += taken.filter { !draft.files.contains($0) }
            browser.handOverToTextForm()
        }
    }
}

/// A chip of the new-item line, 26 points tall with corners of 8 on the gray wash: what it sets in secondary, then its
/// value in primary, as "Due Fri 27 Nov". A chip with no value yet shows only what it sets.
struct LineChip: View {
    let name: String
    let value: String?
    /// Whether the chip has the keyboard, so Delete would put it back.
    let isChosen: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 5) {
            Text(verbatim: name)
                .fontWeight(.regular)
                .foregroundStyle(.secondary)
            if let value {
                Text(verbatim: value)
                    .foregroundStyle(.primary)
                    .truncationMode(.middle)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .lineLimit(1)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .frame(maxWidth: 300)
        .background(ChipLooks.current.chipWash(for: scheme), in: .rect(cornerRadius: 8))
        .overlay {
            if isChosen { AppButtonStyle.focusRing(AnyShape(.rect(cornerRadius: 8))) }
        }
        .contentShape(.rect(cornerRadius: 8))
    }
}
