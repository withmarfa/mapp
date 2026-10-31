import MarfaIcons
import SwiftUI
import UniformTypeIdentifiers

/// ⌘N, the toolbar's New Item and the palette's New commands: a panel near the top of the window for making one
/// item. What it holds comes first (a title and text, a file, or a title alone); above the footer, chips show the
/// details the person added, its properties and parent, and the files to attach to it. The footer chooses the
/// kind of item and, from the plus menu, adds a file or a detail. ⌘Return adds it and opens it. Escape, Cancel or a click outside puts it away, keeping what was typed and given for the window; an empty panel also goes when the window stops being in front.
struct QuickAddPanel: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @Environment(\.undoManager) private var undoManager
    @AppStorage(QuickAdd.lastTypeKey) private var lastType = ""
    let browser: Browser
    @Bindable var quickAdd: QuickAdd
    let editor: EditorController
    @FocusState private var focus: Field?
    @State private var bodySelection: TextSelection?
    /// The field, or the parent (`parentEditingKey`), whose popover is open.
    @State private var editing: String?
    @State private var isChoosingFile = false
    @State private var isDropTargeted = false
    /// Where the keyboard was before the panel took it, and goes back to once the panel is put away.
    @State private var returnFocus: Browser.Pane = .list

    private enum Field: Hashable { case title, body }

    var body: some View {
        if let draft = quickAdd.draft {
            content(draft)
        }
    }

    private func content(_ draft: QuickAdd.Draft) -> some View {
        let catalogue = library.catalogue
        let isFile = QuickAdd.isFile(draft.typeID, in: catalogue)
        let showsBody = QuickAdd.showsBody(draft, in: catalogue)
        let holdsFiles = QuickAdd.holdsFilesItCannotKeep(draft, in: catalogue)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if isFile, !holdsFiles { fileArea(draft) }
                titleField(isFile: isFile)
                if showsBody { bodyField(draft) }
                if QuickAdd.holdsTextItCannotKeep(draft, in: catalogue) {
                    Text("This kind of item doesn’t keep text. Remove the text, or choose another kind.")
                        .interfaceFont(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("QuickAddTextNotKept")
                }
                if holdsFiles {
                    Text("A file item holds one file. Remove the others, or choose another kind.")
                        .interfaceFont(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("QuickAddFilesNotKept")
                }
                if let list = quickAdd.unfinishedLists.first {
                    Text("\(list.displayLabel) has an entry that isn’t finished. Finish it, or cancel it, to add the item.")
                        .interfaceFont(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("QuickAddListUnfinished")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            Spacer(minLength: 0)
            // Files that are chips of their own are a note's attachments, or a file item's extra files.
            chipRow(draft, files: !isFile || holdsFiles ? draft.files : [])
            Divider()
                .padding(.top, 14)
            bottomBar(draft, isFile: isFile)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
        }
        .frame(minHeight: 300)
        .floatingPanelSurface(width: 620)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        // Files dropped or pasted anywhere on the panel are the file of a file item, or attachments of any other.
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            take(providers)
        }
        .onPasteCommand(of: [.fileURL]) { providers in
            _ = take(providers)
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.item], allowsMultipleSelection: !isFile) { result in
            if case .success(let urls) = result { take(urls) }
        }
        .onKeyPress(.escape) {
            putAway()
            return .handled
        }
        // An empty panel does not wait in a window the person has left. The file importer and the popovers take the
        // key for a moment, and are not leaving.
        .onWindowResignsKey { keyWindowIsOwn in
            browser.putAwayQuickAddLeftEmpty(usesOwnSurface: isChoosingFile || editing != nil, keyWindowIsOwn: keyWindowIsOwn)
        }
        .onAppear { returnFocus = editor.isFocused ? .page : .list }
        .defaultFocus($focus, .title)
        .task {
            // Asked any sooner, the field is not yet in the window and the list keeps the keyboard.
            try? await Task.sleep(for: .milliseconds(50))
            focus = .title
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New Item")
        .accessibilityIdentifier("QuickAddPanel")
    }

    // MARK: Kind

    /// The kind of item, as a pop-up button showing its symbol and name.
    private func typePicker(_ draft: QuickAdd.Draft) -> some View {
        let shown = QuickAdd.typeIDs(of: SidebarPlan(library, layout: libraries.sidebarLayout).shownTypes)
        let (first, rest) = QuickAdd.kindMenu(QuickAdd.types(in: library), shown: shown, chosen: draft.typeID)
        return Picker("Kind", selection: Binding { draft.typeID } set: { choose($0) }) {
            ForEach(first) { type in kindLabel(type).tag(type.id.rawValue) }
            if !rest.isEmpty {
                Divider()
                ForEach(rest) { type in kindLabel(type).tag(type.id.rawValue) }
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help("Kind of Item")
        .accessibilityLabel("Kind of Item")
        .accessibilityIdentifier("QuickAddType")
    }

    private func kindLabel(_ type: ItemTypeOption) -> some View {
        Label(type.label, typeIcon: library.catalogue.icon(for: type.id))
    }

    private func choose(_ typeID: String) {
        browser.chooseQuickAddType(typeID, in: library)
        editing = nil
    }

    /// Tab and Shift-Tab move through the kinds while nothing is typed; once something is, they move between the
    /// fields as usual.
    private func cycleType(backward: Bool) -> KeyPress.Result {
        guard let draft = quickAdd.draft, !quickAdd.holdsContent else { return .ignored }
        let types = QuickAdd.types(in: library)
        let shown = QuickAdd.typeIDs(of: SidebarPlan(library, layout: libraries.sidebarLayout).shownTypes)
        let chips = QuickAdd.kindMenu(types, shown: shown, chosen: draft.typeID).first
        guard let index = chips.firstIndex(where: { $0.id.rawValue == draft.typeID }), chips.count > 1 else { return .ignored }
        let next = (index + (backward ? chips.count - 1 : 1)) % chips.count
        choose(chips[next].id.rawValue)
        return .handled
    }

    // MARK: What it holds

    private func titleField(isFile: Bool) -> some View {
        TextField(isFile ? "Title (Optional)" : "Title", text: Binding { quickAdd.draft?.title ?? "" } set: { quickAdd.draft?.title = $0 })
            .textFieldStyle(.plain)
            .interfaceFont(isFile ? .title3 : .title2.weight(.semibold))
            .focused($focus, equals: .title)
            .onSubmit { focus = .body }
            .onExitCommand { putAway() }
            .onKeyPress(keys: [.tab, KeyEquivalent("\u{19}")]) { press in
                cycleType(backward: press.modifiers.contains(.shift) || press.key == KeyEquivalent("\u{19}"))
            }
            .accessibilityIdentifier("QuickAddTitle")
    }

    private func bodyField(_ draft: QuickAdd.Draft) -> some View {
        // The hidden copy of the text sizes the editor, so it grows with what is typed and scrolls past its limit.
        Text(verbatim: draft.body + "\n")
            .interfaceFont(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hidden()
            .frame(minHeight: 120, maxHeight: 320, alignment: .top)
            .overlay {
                ZStack(alignment: .topLeading) {
                    // The text view pads each line by its line fragment padding; moving it out by that much lines its text up with the title's.
                    TextEditor(text: Binding { quickAdd.draft?.body ?? "" } set: { quickAdd.draft?.body = $0 }, selection: $bodySelection)
                        .textEditorStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .interfaceFont(.body)
                        .padding(.horizontal, -5)
                        .focused($focus, equals: .body)
                        .onExitCommand { putAway() }
                        .accessibilityIdentifier("QuickAddBody")
                    if draft.body.isEmpty {
                        Text("Add Text")
                            .interfaceFont(.body)
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
            .onChange(of: bodySelection) { recordCaret() }
    }

    /// Keeps where the caret is in the text, so the page puts it back there.
    private func recordCaret() {
        guard let body = quickAdd.draft?.body, case .selection(let range)? = bodySelection?.indices,
              range.upperBound <= body.endIndex else { return }
        quickAdd.draft?.caret = body.distance(from: body.startIndex, to: range.upperBound)
    }

    private func fileArea(_ draft: QuickAdd.Draft) -> some View {
        let catalogue = library.catalogue
        return Button {
            isChoosingFile = true
        } label: {
            VStack(spacing: 6) {
                if let file = draft.files.first {
                    TypeIcon(id: catalogue.icon(for: .file))
                        .font(.title)
                    Text(verbatim: file.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let byteCount = file.byteCount {
                        Text(byteCount, format: .byteCount(style: .file))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "arrow.down.document")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("Drop a File, Paste One, or Click to Choose")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .accessibilityIdentifier("QuickAddFile")
    }

    /// The files to attach, or a file item's files while it holds more than one, each with a button to remove it.
    private func attachmentChip(_ file: QuickAdd.File) -> some View {
        chipShell(remove: (String(localized: "Remove “\(file.name)”"), "QuickAddRemoveAttachment", { quickAdd.draft?.files.removeAll { $0 == file } })) {
            chipFace(hasRemove: true) {
                HStack(spacing: 6) {
                    TypeIcon(id: library.catalogue.icon(for: .file))
                        .foregroundStyle(.secondary)
                    Text(verbatim: file.name)
                        .truncationMode(.middle)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(file.name)
        .accessibilityIdentifier("QuickAddAttachment")
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

    /// Takes files given to the panel: the file of a file item, replacing the one it had, or attachments of any
    /// other kind. Each is read only when the item is added; a folder or a file that cannot be read is told now.
    private func take(_ urls: [URL]) {
        guard let draft = quickAdd.draft else { return }
        var taken: [QuickAdd.File] = []
        var unreadable: [String] = []
        for url in urls {
            if let file = QuickAdd.File(url) { taken.append(file) } else { unreadable.append("“\(url.lastPathComponent)”") }
        }
        QuickAdd.File.tellUnreadable(unreadable, to: library.notices)
        guard !taken.isEmpty else { return }
        if QuickAdd.isFile(draft.typeID, in: library.catalogue) {
            quickAdd.draft?.files = taken
        } else {
            quickAdd.draft?.files += taken.filter { !draft.files.contains($0) }
        }
        if focus == nil { focus = .title }
    }

    // MARK: Properties

    /// A chip's height. The text inside is the interface's body size, so a larger base text size grows it.
    private static let chipHeight: CGFloat = 28
    private static let chipMaxWidth: CGFloat = 260

    /// The chips the person added and the files to attach, left to right and wrapping, at the foot of the text.
    @ViewBuilder
    private func chipRow(_ draft: QuickAdd.Draft, files: [QuickAdd.File]) -> some View {
        let catalogue = library.catalogue
        let chips = QuickAdd.shownChips(draft, in: catalogue)
        if !chips.isEmpty || !files.isEmpty {
            TagFlowLayout(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    switch chip {
                    case .parent:
                        parentChip(draft)
                    case .field(let key):
                        if let field = QuickAdd.fields(of: draft.typeID, in: catalogue).first(where: { $0.key == key }) {
                            propertyChip(field, value: draft.properties[key], typeID: draft.typeID)
                        }
                    }
                }
                ForEach(files) { file in attachmentChip(file) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Details")
            .accessibilityIdentifier("QuickAddChips")
        }
    }

    /// A chip's capsule, with its remove button inside the trailing end unless `remove` is nil. It is drawn here,
    /// not by a bordered button, since a system button cannot hold a second button; its fill and edge are the
    /// system's. It is as wide as what it says, up to `chipMaxWidth` and the row, and cuts the text to that.
    private func chipShell<Main: View>(
        remove: (label: String, identifier: String, action: () -> Void)?, @ViewBuilder main: () -> Main
    ) -> some View {
        HStack(spacing: 0) {
            main()
            if let remove {
                removeButton(remove.label, identifier: remove.identifier, action: remove.action)
            }
        }
        .interfaceFont(.body)
        .background(.fill.quaternary, in: .capsule)
        .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
        .frame(maxWidth: Self.chipMaxWidth)
    }

    /// What a chip says, with the room its capsule needs around it; the whole of it takes the click.
    private func chipFace<Content: View>(hasRemove: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .lineLimit(1)
            .padding(.leading, 12)
            .padding(.trailing, hasRemove ? 4 : 12)
            .frame(minHeight: Self.chipHeight)
            .contentShape(.rect)
    }

    private func removeButton(_ label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: "xmark.circle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .frame(minHeight: Self.chipHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 4)
        .help("Remove")
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private func propertyChip(_ field: ItemTypeInfo.Field, value: PropertyValue?, typeID: String) -> some View {
        let isRemovable = QuickAdd.isRemovable(.field(field.key), typeID: typeID, in: library.catalogue)
        let hasValue = value.map { $0 != .null } ?? false
        let shownValue = value.flatMap { hasValue ? QuickAdd.valueText($0, in: field) : nil }
        let name = field.displayLabel
        let remove: () -> Void = {
            if editing == field.key { editing = nil }
            quickAdd.draft?.remove(.field(field.key), in: library.catalogue)
            quickAdd.listDrafts[field.key] = nil
        }
        return chipShell(remove: isRemovable ? (String(localized: "Remove \(name)"), "QuickAddRemove.\(field.key)", remove) : nil) {
            Button {
                if field.kind.isList { _ = quickAdd.listDraft(for: field.key) }
                editing = field.key
            } label: {
                chipFace(hasRemove: isRemovable) {
                    if let shownValue {
                        Text(verbatim: "\(name): \(shownValue)")
                    } else {
                        Text("Set \(name)")
                            .foregroundStyle(field.required ? .primary : .secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding { editing == field.key } set: { if !$0, editing == field.key { editing = nil } }, arrowEdge: .top) {
                // A list's entry being added outlives the popover, in the window's quick add.
                let listDraft = field.kind.isList ? quickAdd.listDraft(for: field.key) : nil
                ItemPropertyRow(definition: field, value: value, isEditable: true, onChange: { newValue in
                    quickAdd.draft?.properties[field.key] = newValue
                    return true
                }, retainedDraft: listDraft, startsEditing: true, handsOffOnLeave: listDraft == nil)
                .padding(14)
                .frame(width: 340)
            }
            .accessibilityLabel(name)
            .accessibilityValue(shownValue ?? String(localized: "Not Set"))
            .accessibilityIdentifier("QuickAddProperty.\(field.key)")
        }
        .contextMenu {
            if isRemovable { Button("Remove", action: remove) }
        }
    }

    /// What `editing` holds while the parent's list is open; no field key can be this, since keys have no spaces.
    private static let parentEditingKey = "the parent"

    /// The parent as a chip: a popover list of the items the kind can go under.
    private func parentChip(_ draft: QuickAdd.Draft) -> some View {
        let title = draft.parentID.flatMap { library.item($0)?.title } ?? String(localized: "Item not found")
        let name = String(localized: "Parent")
        let remove: () -> Void = {
            if editing == Self.parentEditingKey { editing = nil }
            quickAdd.draft?.remove(.parent, in: library.catalogue)
        }
        return chipShell(remove: (String(localized: "Remove \(name)"), "QuickAddRemoveParent", remove)) {
            Button {
                editing = Self.parentEditingKey
            } label: {
                chipFace(hasRemove: true) {
                    Text(verbatim: "\(name): \(title)")
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: parentPopover(isOpen: { true }), arrowEdge: .top) { parentList(draft) }
            .accessibilityLabel(name)
            .accessibilityValue(title)
            .accessibilityIdentifier("QuickAddParent")
        }
        .contextMenu {
            Button("Remove", action: remove)
        }
    }

    /// Whether the parent's list is open, while `isOpen` allows it.
    private func parentPopover(isOpen: @escaping () -> Bool) -> Binding<Bool> {
        Binding { editing == Self.parentEditingKey && isOpen() } set: { if !$0, editing == Self.parentEditingKey { editing = nil } }
    }

    /// The items the draft's kind can go under, and a tick beside the one chosen. The list is built only when the
    /// popover opens, since finding the items reads the whole library.
    private func parentList(_ draft: QuickAdd.Draft) -> some View {
        let candidates = parentCandidates(draft)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(candidates) { candidate in
                    Button {
                        quickAdd.draft?.setParent(candidate.id)
                        editing = nil
                    } label: {
                        HStack {
                            Label { Text(candidate.displayTitle) } icon: { TypeIcon(id: library.catalogue.icon(for: candidate.type)) }
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if candidate.id == draft.parentID {
                                Image(systemName: "checkmark")
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: Self.chipHeight)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
        }
        .interfaceFont(.body)
        .frame(width: 320)
        .frame(maxHeight: 320)
    }

    // MARK: Place and adding

    private func bottomBar(_ draft: QuickAdd.Draft, isFile: Bool) -> some View {
        let label = QuickAdd.types(in: library).first { $0.id.rawValue == draft.typeID }?.label ?? ""
        return HStack(spacing: 8) {
            typePicker(draft)
            moreMenu(draft, isFile: isFile)
            Spacer(minLength: 12)
            Button("Cancel") { putAway() }
                .accessibilityIdentifier("QuickAddCancel")
            Button {
                save()
            } label: {
                HStack(spacing: 6) {
                    Text("Add \(label)")
                    Text(verbatim: "⌘↩")
                        .opacity(0.7)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!QuickAdd.canSave(draft, in: library) || quickAdd.isSaving || !quickAdd.unfinishedLists.isEmpty)
            .accessibilityIdentifier("QuickAddAdd")
        }
        .controlSize(.large)
    }

    /// The plus beside the kind: attaches a file (or chooses a file item's file), puts the item under a parent, or
    /// shows a field of the kind as a chip. What is already a chip is not listed again. A file item takes no field.
    /// The parent is chosen from a popover on the plus, so the items are looked up only once it opens.
    private func moreMenu(_ draft: QuickAdd.Draft, isFile: Bool) -> some View {
        let catalogue = library.catalogue
        let offered = QuickAdd.offeredChips(draft, in: catalogue, canHaveParent: library.canHaveParent(typeID: draft.typeID))
        let fields = QuickAdd.fields(of: draft.typeID, in: catalogue)
        return Menu {
            Button(isFile ? "Choose File…" : "Attach File…", systemImage: "paperclip") { isChoosingFile = true }
                .accessibilityIdentifier("QuickAddAttach")
            if !offered.isEmpty { Divider() }
            ForEach(offered, id: \.self) { chip in
                switch chip {
                case .parent:
                    Button("Choose Parent…", systemImage: "arrow.turn.left.up") { open(Self.parentEditingKey) }
                        .accessibilityIdentifier("QuickAddMoreParent")
                case .field(let key):
                    if let field = fields.first(where: { $0.key == key }) {
                        Button(field.displayLabel) {
                            quickAdd.draft?.add(.field(key))
                            if field.kind.isList { _ = quickAdd.listDraft(for: key) }
                            open(key)
                        }
                        .accessibilityIdentifier("QuickAddMore.\(key)")
                    }
                }
            }
        } label: {
            Label("Add File or Property", systemImage: "plus")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .fixedSize()
        .popover(isPresented: parentPopover(isOpen: { quickAdd.draft?.parentID == nil }), arrowEdge: .top) { parentList(draft) }
        .help("Add File or Property")
        .accessibilityLabel("Add File or Property")
        .accessibilityIdentifier("QuickAddMore")
    }

    /// Opens a popover once the menu that chose it has closed and a chip it belongs to is in the view, since a
    /// popover asked for in the same update has nothing to attach to yet.
    private func open(_ key: String) {
        Task { editing = key }
    }

    /// The items the draft's kind can go under, with the one already chosen first if the kind no longer lists it.
    private func parentCandidates(_ draft: QuickAdd.Draft) -> [Item] {
        var candidates = library.creationParentCandidates(typeID: draft.typeID)
        if let parentID = draft.parentID, !candidates.contains(where: { $0.id == parentID }), let parent = library.item(parentID) {
            candidates.insert(parent, at: 0)
        }
        return candidates
    }

    private func save() {
        guard let typeID = quickAdd.draft?.typeID else { return }
        Task {
            guard await browser.saveQuickAdd(in: library, undoManager: undoManager) != nil else { return }
            lastType = typeID
        }
    }

    private func putAway() {
        browser.putAwayQuickAdd()
        if browser.focusRequest == nil { browser.focusRequest = returnFocus }
    }
}
