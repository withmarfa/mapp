import SwiftUI
import UniformTypeIdentifiers

/// ⌘N, the toolbar's New Item and the palette's New commands: a panel in the middle of the window for making one
/// item. What it holds comes first (a title and text, a file, or a title alone), then its properties; the footer
/// chooses the kind of item and where it goes. ⌘Return adds it and opens it. Escape, Cancel or a click outside
/// puts it away, keeping what was typed for the window.
struct QuickAddPanel: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @Environment(\.undoManager) private var undoManager
    @AppStorage(QuickAdd.lastTypeKey) private var lastType = ""
    @AppStorage(QuickAdd.pinsKey) private var pinsText = ""
    let browser: Browser
    @Bindable var quickAdd: QuickAdd
    let editor: EditorController
    @FocusState private var focus: Field?
    @State private var bodySelection: TextSelection?
    /// The field whose popover is open.
    @State private var editing: String?
    /// Fields chosen from the add menu this time, shown though not kept.
    @State private var added: [String] = []
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
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if isFile { fileArea(draft) }
                titleField(isFile: isFile)
                if showsBody { bodyField(draft) }
                if QuickAdd.holdsTextItCannotKeep(draft, in: catalogue) {
                    Text("This kind of item doesn’t keep text. Remove the text, or choose another kind.")
                        .interfaceFont(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("QuickAddTextNotKept")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            Spacer(minLength: 0)
            propertyChips(draft)
                .padding(.horizontal, 20)
                .padding(.top, 14)
            Divider()
                .padding(.top, 16)
            bottomBar(draft, isFile: isFile)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
        }
        .frame(minHeight: 300)
        .floatingPanelSurface(width: 620)
        .onKeyPress(.escape) {
            putAway()
            return .handled
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
        Label(type.label, systemImage: TypeSymbol.name(for: type.id, in: library.catalogue))
    }

    private func choose(_ typeID: String) {
        browser.chooseQuickAddType(typeID, in: library)
        added = []
        editing = nil
    }

    /// Tab and Shift-Tab move through the kinds while nothing is typed; once something is, they move between the
    /// fields as usual.
    private func cycleType(backward: Bool) -> KeyPress.Result {
        guard let draft = quickAdd.draft, !draft.hasContent else { return .ignored }
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
        Button {
            isChoosingFile = true
        } label: {
            VStack(spacing: 6) {
                if let file = draft.file {
                    Image(systemName: "doc")
                        .font(.title)
                    Text(verbatim: file.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(Int64(file.data.count), format: .byteCount(style: .file))
                        .foregroundStyle(.secondary)
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
        .background(isDropTargeted ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                              style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            take(providers)
        }
        .onPasteCommand(of: [.fileURL]) { providers in
            _ = take(providers)
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { take(url) }
        }
        .accessibilityIdentifier("QuickAddFile")
    }

    private func take(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: URL.self) }) else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in take(url) }
        }
        return true
    }

    private func take(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            library.notices.tell(
                String(localized: "Can’t Add File"),
                String(localized: "MAPP couldn’t read “\(url.lastPathComponent)”."))
            return
        }
        quickAdd.draft?.file = QuickAdd.File(name: url.lastPathComponent, data: data)
        focus = .title
    }

    // MARK: Properties

    private func propertyChips(_ draft: QuickAdd.Draft) -> some View {
        let fields = QuickAdd.fields(of: draft.typeID, in: library.catalogue)
        let pinned = Set(pins[draft.typeID] ?? [])
        let shown = fields.filter { $0.required || pinned.contains($0.key) || added.contains($0.key) || draft.properties[$0.key] != nil }
        let rest = fields.filter { field in !shown.contains(field) }
        return HStack(spacing: 6) {
            ForEach(shown) { field in
                propertyChip(field, value: draft.properties[field.key], typeID: draft.typeID, isPinned: pinned.contains(field.key))
            }
            if !rest.isEmpty {
                Menu {
                    ForEach(rest) { field in
                        Button(field.displayLabel) {
                            added.append(field.key)
                            editing = field.key
                        }
                    }
                } label: {
                    Label("Add Property", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add Property")
                .accessibilityIdentifier("QuickAddAddProperty")
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
    }

    private func propertyChip(_ field: ItemTypeInfo.Field, value: PropertyValue?, typeID: String, isPinned: Bool) -> some View {
        Button {
            editing = field.key
        } label: {
            if let value, value != .null {
                Text(verbatim: "\(field.displayLabel): \(Self.text(of: value, in: field))")
                    .lineLimit(1)
            } else {
                Text(verbatim: field.displayLabel)
                    .foregroundStyle(field.required ? .primary : .secondary)
            }
        }
        .popover(isPresented: Binding { editing == field.key } set: { if !$0, editing == field.key { editing = nil } }, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                ItemPropertyRow(definition: field, value: value, isEditable: true, onChange: { newValue in
                    quickAdd.draft?.properties[field.key] = newValue
                    return true
                }, startsEditing: true)
                if !field.required {
                    Divider()
                    Toggle("Always Show", isOn: Binding { isPinned } set: { pin(field.key, $0, typeID: typeID) })
                        .toggleStyle(.checkbox)
                }
            }
            .padding(14)
            .frame(width: 340)
        }
        .accessibilityIdentifier("QuickAddProperty.\(field.key)")
    }

    /// A value as its chip shows it: a choice by its label, a Boolean as Yes or No, anything else as written.
    private static func text(of value: PropertyValue, in field: ItemTypeInfo.Field) -> String {
        if field.kind == .boolean, case .bool(let flag) = value { return flag ? String(localized: "Yes") : String(localized: "No") }
        if field.isPicked, let option = value.string { return String(localized: String.LocalizationValue(ItemTypeInfo.Field.label(ofOption: option))) }
        return ItemValueText.string(value)
    }

    private var pins: [String: [String]] { QuickAdd.pins(from: pinsText)[libraries.sidebarLayoutKey] ?? [:] }

    private func pin(_ key: String, _ pinned: Bool, typeID: String) {
        pinsText = QuickAdd.text(of: QuickAdd.pinning(key, pinned, typeID: typeID, library: libraries.sidebarLayoutKey, in: QuickAdd.pins(from: pinsText)))
    }

    // MARK: Place and adding

    private func bottomBar(_ draft: QuickAdd.Draft, isFile: Bool) -> some View {
        let label = QuickAdd.types(in: library).first { $0.id.rawValue == draft.typeID }?.label ?? ""
        return HStack(spacing: 8) {
            typePicker(draft)
            if !isFile { parentPicker(draft) }
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
            .disabled(!QuickAdd.canSave(draft, in: library.catalogue) || quickAdd.isSaving)
            .accessibilityIdentifier("QuickAddAdd")
        }
        .controlSize(.large)
    }

    /// Where the item goes, as a pop-up button: no parent, or one of the items its kind can go under.
    private func parentPicker(_ draft: QuickAdd.Draft) -> some View {
        var candidates = library.creationParentCandidates(typeID: draft.typeID)
        if let parentID = draft.parentID, !candidates.contains(where: { $0.id == parentID }), let parent = library.item(parentID) {
            candidates.insert(parent, at: 0)
        }
        return Picker("Parent", selection: Binding { draft.parentID } set: { quickAdd.draft?.parentID = $0 }) {
            Label("No Parent", systemImage: "tray").tag(ItemID?.none)
            if !candidates.isEmpty { Divider() }
            ForEach(candidates) { candidate in
                Label(candidate.title, systemImage: TypeSymbol.name(for: candidate.type, in: library.catalogue))
                    .tag(Optional(candidate.id))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .disabled(candidates.isEmpty)
        .help("Parent")
        .accessibilityLabel("Parent")
        .accessibilityIdentifier("QuickAddParent")
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
