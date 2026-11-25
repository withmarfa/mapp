import MarfaIcons
import SwiftUI
import UniformTypeIdentifiers

/// ⌘N and every New, unless Settings > General > New Opens says Text Form: one line that makes an item. The kind is
/// the capsule at its start, which Tab moves on; `#` adds a tag, `@` a parent and `/` a property of the kind, each
/// from a list of matches; a day typed is the item's due or start date; a pasted web address makes a bookmark. Return
/// adds it and leaves the line open, empty, with the same kind; ⌘Return adds it and opens it; ⇧Return hands everything
/// typed to the text form. Escape or a click outside puts it away, keeping what was typed (`NewItemDrafts`).
///
/// The window shows it over its content, with the window's toast; over another app it stands in a panel of its own
/// (`NewItemAnywhere`), with an Added message and Undo in the panel.
struct NewItemLinePanel: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @Environment(\.undoManager) private var windowUndo
    let browser: Browser
    @Bindable var quickAdd: QuickAdd
    /// The window's toast, or nil over another app.
    var toasts: ToastPresenter?
    /// The panel's own undo manager, over another app, where no window gives one.
    var undoManager: UndoManager?
    /// What Add and Open does over another app, where the line's own browser has no window to open the item in.
    var opensElsewhere: ((ItemID, String) -> Void)?
    let onClose: () -> Void

    @FocusState private var isFieldFocused: Bool
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
        let matches = matches(for: draft)
        return VStack(alignment: .leading, spacing: 0) {
            fieldRow(draft)
                .frame(minHeight: 62)
                .padding(.horizontal, 16)
            Divider()
            Group {
                if let matches {
                    matchList(matches)
                } else {
                    keyRows(draft)
                }
            }
            .padding(.vertical, 8)
            if let lastAdded = quickAdd.lastAdded {
                addedLine(lastAdded)
            }
            Divider()
            foot(draft)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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
            isFieldFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New Item")
        .accessibilityIdentifier("NewItemLine")
    }

    // MARK: The line

    private func fieldRow(_ draft: QuickAdd.Draft) -> some View {
        let catalogue = library.catalogue
        return HStack(spacing: 8) {
            kindPill(draft)
            TagFlowLayout(spacing: 6) {
                ForEach(draft.tags, id: \.self) { tag in
                    LineToken(text: tag, mark: .symbol("number"), remove: String(localized: "Remove Tag “\(tag)”")) {
                        quickAdd.draft?.tags.removeAll { $0 == tag }
                    }
                }
                if let parent = draft.parentID {
                    let title = library.item(parent)?.displayTitle ?? String(localized: "Item not found")
                    LineToken(text: title, mark: .symbol("arrow.turn.left.up"), remove: String(localized: "Remove Parent")) {
                        quickAdd.draft?.remove(.parent, in: catalogue)
                    }
                }
                ForEach(propertyKeys(draft), id: \.self) { key in
                    if let field = QuickAdd.fields(of: draft.typeID, in: catalogue).first(where: { $0.key == key }) {
                        propertyToken(field, value: draft.properties[key], typeID: draft.typeID)
                    }
                }
                if let found = QuickAdd.foundDay(in: draft, catalogue: catalogue, now: .now, calendar: .current, locale: .current) {
                    LineToken(
                        text: "\(found.field.label): \(found.day.date.formatted(found.day.hasTime ? .dateTime.weekday().day().month().hour().minute() : .dateTime.weekday().day().month()))",
                        mark: .symbol("calendar"), remove: String(localized: "Keep “\(found.day.phrase)” as Text")
                    ) {
                        browser.declineLineDay(found.day.phrase)
                    }
                    .accessibilityIdentifier("NewItemLineDay")
                }
                if QuickAdd.isFile(draft.typeID, in: catalogue) { fileToken(draft) }
                titleField(draft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
    }

    /// The kind, as a tinted capsule whose menu lists the kinds the line can make.
    private func kindPill(_ draft: QuickAdd.Draft) -> some View {
        let kinds = lineKinds(draft)
        let chosen = kinds.first { $0.id.rawValue == draft.typeID }
        let label = chosen?.label ?? library.catalogue.label(for: TypeID(draft.typeID))
        return Menu {
            Picker("Kind", selection: Binding { draft.typeID } set: { browser.chooseQuickAddType($0, in: library) }) {
                ForEach(kinds) { type in
                    Label(type.label, typeIcon: library.catalogue.icon(for: type.id)).tag(type.id.rawValue)
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

    private func titleField(_ draft: QuickAdd.Draft) -> some View {
        TextField(QuickAdd.linePlaceholder(draft, in: library.catalogue), text: Binding {
            quickAdd.draft?.title ?? ""
        } set: { text in
            let old = quickAdd.draft?.title ?? ""
            quickAdd.draft?.title = text
            browser.lineTextChanged(from: old, in: library)
            highlighted = 0
        })
        .textFieldStyle(.plain)
        .interfaceFont(.title3)
        .frame(minWidth: 160)
        .focused($isFieldFocused)
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
        .accessibilityIdentifier("NewItemLineTitle")
    }

    /// The property keys shown as tokens: those the person chose, and any the line filled, such as a bookmark's address.
    private func propertyKeys(_ draft: QuickAdd.Draft) -> [String] {
        draft.chips.compactMap { chip in
            if case .field(let key) = chip { key } else { nil }
        }
    }

    private func propertyToken(_ field: ItemTypeInfo.Field, value: PropertyValue?, typeID: String) -> some View {
        let shown = value.flatMap { $0 == .null ? nil : QuickAdd.valueText($0, in: field) }
        let removable = QuickAdd.isRemovable(.field(field.key), typeID: typeID, in: library.catalogue)
        return LineToken(
            text: shown.map { "\(field.label): \($0)" } ?? String(localized: "Set \(field.label)"),
            mark: nil, remove: removable ? String(localized: "Remove \(field.label)") : nil,
            onTap: { editing = field.key }
        ) {
            if editing == field.key { editing = nil }
            quickAdd.draft?.remove(.field(field.key), in: library.catalogue)
        }
        .popover(isPresented: Binding { editing == field.key } set: { if !$0, editing == field.key { editing = nil } }, arrowEdge: .bottom) {
            ItemPropertyRow(definition: field, value: value, isEditable: true, onChange: { newValue in
                quickAdd.draft?.properties[field.key] = newValue
                return true
            }, retainedDraft: field.kind.isList ? quickAdd.listDraft(for: field.key) : nil, startsEditing: true,
               handsOffOnLeave: !field.kind.isList)
            .padding(14)
            .frame(width: 340)
        }
        .accessibilityIdentifier("NewItemLineProperty.\(field.key)")
    }

    /// A file item's file: the one chosen, or a button to choose one, which a drop on the panel also gives.
    private func fileToken(_ draft: QuickAdd.Draft) -> some View {
        Group {
            if let file = draft.files.first {
                LineToken(text: file.name, mark: .symbol("doc"), remove: String(localized: "Remove “\(file.name)”")) {
                    quickAdd.draft?.files = []
                }
            } else {
                HStack(spacing: 6) {
                    Button("Choose a File…") { isChoosingFile = true }
                        .appButton(.secondary, size: .small)
                        .accessibilityIdentifier("NewItemLineChooseFile")
                    Text("or drop one here")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Rows under the line

    /// One thing the line can be given, with its key and what was used last, before anything is typed.
    private func keyRows(_ draft: QuickAdd.Draft) -> some View {
        let recents = NewItemRecents.stored(for: library.serverKey, in: browser.defaults)
        let kinds = lineKinds(draft)
        let recentKinds = recents.kinds.compactMap { id in kinds.first { $0.id.rawValue == id } }
        let canHaveParent = library.canHaveParent(typeID: draft.typeID)
        let recentParents = canHaveParent ? recents.parents.compactMap { library.item($0) } : []
        let fields = offeredFields(draft, query: "")
        return VStack(alignment: .leading, spacing: 0) {
            keyRow("Kind", key: "⇥") {
                ForEach(recentKinds.prefix(4)) { type in
                    suggestion(type.label, icon: library.catalogue.icon(for: type.id)) { browser.chooseLineMatch(.kind(type.id.rawValue), in: library) }
                }
            }
            keyRow("Tag", key: "#") {
                ForEach(recents.tags.prefix(4), id: \.self) { tag in
                    suggestion("#\(tag)", icon: nil) { browser.chooseLineMatch(.tag(tag), in: library) }
                }
            }
            if canHaveParent {
                keyRow("Parent", key: "@") {
                    ForEach(recentParents.prefix(3)) { item in
                        suggestion(item.displayTitle, icon: library.catalogue.icon(for: item.type)) { browser.chooseLineMatch(.parent(item.id), in: library) }
                    }
                }
            }
            if !fields.isEmpty {
                keyRow("Property", key: "/") {
                    ForEach(fields.prefix(3), id: \.key) { field in
                        suggestion(field.label, icon: nil) { chooseField(field.key) }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func keyRow<Suggestions: View>(_ title: LocalizedStringKey, key: String, @ViewBuilder suggestions: () -> Suggestions) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 70, alignment: .leading)
            KeyCap(key: key)
                .frame(width: 26)
            HStack(spacing: 6) { suggestions() }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(minHeight: 30)
    }

    private func suggestion(_ text: String, icon: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { TypeGlyph(id: icon) }
                Text(verbatim: text).lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    /// One match for the marked word being typed.
    private struct Match: Identifiable {
        let id: String
        let text: String
        let icon: String?
        let detail: String?
        let choice: Browser.LineChoice?
        let field: String?
    }

    /// The matches for the marked word at the end of the line, or nil while none is being typed.
    private func matches(for draft: QuickAdd.Draft) -> [Match]? {
        guard let typing = NewItemText.typing(in: draft.title) else { return nil }
        let query = typing.query
        func fits(_ text: String) -> Bool { query.isEmpty || text.localizedStandardContains(query) }
        switch typing.mark {
        case .tag:
            let recents = NewItemRecents.stored(for: library.serverKey, in: browser.defaults).tags
            var tags = recents + library.knownTags.filter { !recents.contains($0) }
            tags = tags.filter { fits($0) && !draft.tags.contains($0) && !library.reservedTags.contains($0) }
            var found = tags.prefix(6).map { Match(id: "tag:" + $0, text: "#" + $0, icon: nil, detail: nil, choice: .tag($0), field: nil) }
            if !query.isEmpty, !tags.contains(query) {
                found.append(Match(id: "new:" + query, text: "#" + query, icon: nil, detail: String(localized: "New Tag"), choice: .tag(query), field: nil))
            }
            return found
        case .parent:
            guard library.canHaveParent(typeID: draft.typeID) else { return [] }
            let recents = NewItemRecents.stored(for: library.serverKey, in: browser.defaults).parents
            let candidates = library.creationParentCandidates(typeID: draft.typeID)
            let ordered = recents.compactMap { id in candidates.first { $0.id == id } } + candidates.filter { !recents.contains($0.id) }
            return ordered.filter { fits($0.displayTitle) }.prefix(6).map { item in
                Match(
                    id: "parent:" + item.id.rawValue, text: item.displayTitle, icon: library.catalogue.icon(for: item.type),
                    detail: library.catalogue.label(for: item.type), choice: .parent(item.id), field: nil)
            }
        case .property:
            return offeredFields(draft, query: query).map { field in
                Match(id: "field:" + field.key, text: field.label, icon: nil, detail: nil, choice: nil, field: field.key)
            }
        }
    }

    private func matchList(_ matches: [Match]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if matches.isEmpty {
                Text("No Matches")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 30)
            }
            ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                Button { choose(match) } label: {
                    HStack(spacing: 8) {
                        if let icon = match.icon { TypeGlyph(id: icon) }
                        Text(verbatim: match.text).lineLimit(1)
                        Spacer(minLength: 8)
                        if let detail = match.detail { Text(verbatim: detail).foregroundStyle(.secondary) }
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 30)
                    .background(index == highlighted ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("NewItemLineMatch")
            }
        }
        .padding(.horizontal, 6)
    }

    private func choose(_ match: Match) {
        if let choice = match.choice {
            browser.chooseLineMatch(choice, in: library)
        } else if let key = match.field {
            chooseField(key)
        }
        highlighted = 0
        isFieldFocused = true
    }

    private func chooseField(_ key: String) {
        browser.chooseLineMatch(.field(key), in: library)
        Task { editing = key }
    }

    /// The kind's fields the person can still add as a token, matching `query`.
    private func offeredFields(_ draft: QuickAdd.Draft, query: String) -> [ItemTypeInfo.Field] {
        let fields = QuickAdd.fields(of: draft.typeID, in: library.catalogue)
        return QuickAdd.offeredChips(draft, in: library.catalogue, canHaveParent: false).compactMap { chip in
            guard case .field(let key) = chip, let field = fields.first(where: { $0.key == key }) else { return nil }
            return query.isEmpty || field.label.localizedStandardContains(query) ? field : nil
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
        .padding(.horizontal, 16)
        .frame(minHeight: 30)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("NewItemLineAdded")
    }

    // MARK: The foot

    private func foot(_ draft: QuickAdd.Draft) -> some View {
        let canAdd = QuickAdd.canSave(lineFinished(draft), in: library) && !quickAdd.isSaving
            || !QuickAdd.missingRequired(draft, in: library.catalogue).isEmpty
        return HStack(spacing: 8) {
            Text("In")
                .foregroundStyle(.secondary)
            Picker("In", selection: Binding { draft.tier } set: { quickAdd.draft?.tier = $0 }) {
                Text("Library").tag(Tier.library)
                Text("Feed").tag(Tier.feed)
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("NewItemLineIn")
            Spacer(minLength: 12)
            Button {
                browser.handOverToTextForm()
            } label: {
                HStack(spacing: 6) {
                    Text("Add Text")
                    ShortcutKeys("⇧↩").accessibilityHidden(true)
                }
            }
            .appButton(.plain)
            .accessibilityIdentifier("NewItemLineAddText")
            Button {
                add(opening: false)
            } label: {
                HStack(spacing: 6) {
                    Text("Add")
                    ShortcutKeys("↩").accessibilityHidden(true)
                }
            }
            .appButton(.secondary)
            .disabled(!canAdd)
            .accessibilityIdentifier("NewItemLineAdd")
            Button {
                add(opening: true)
            } label: {
                HStack(spacing: 6) {
                    Text("Add and Open")
                    ShortcutKeys("⌘↩", onAccent: true).accessibilityHidden(true)
                }
            }
            .appButton(.primary)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canAdd)
            .accessibilityIdentifier("NewItemLineAddAndOpen")
        }
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
        isFieldFocused = true
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
        let shown = QuickAdd.typeIDs(of: SidebarPlan(library, layout: libraries.sidebarLayout).shownTypes)
        return QuickAdd.lineKinds(QuickAdd.types(in: library), shown: shown, chosen: draft.typeID, in: library.catalogue)
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

/// A value on the new-item line: 26 points tall with corners of 8, its mark, its words and a button to take it out.
struct LineToken: View {
    enum Mark { case symbol(String) }

    let text: String
    let mark: Mark?
    let remove: String?
    var onTap: (() -> Void)?
    let onRemove: () -> Void

    init(text: String, mark: Mark?, remove: String?, onTap: (() -> Void)? = nil, onRemove: @escaping () -> Void) {
        self.text = text
        self.mark = mark
        self.remove = remove
        self.onTap = onTap
        self.onRemove = onRemove
    }

    var body: some View {
        HStack(spacing: 4) {
            Button { onTap?() } label: {
                HStack(spacing: 4) {
                    if case .symbol(let name)? = mark {
                        Image(systemName: name)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .buttonStyle(.plain)
            .disabled(onTap == nil)
            if let remove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(remove)
                .accessibilityLabel(remove)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .frame(maxWidth: 240)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text)
    }
}
