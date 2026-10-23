import AppKit
import SwiftUI

/// The page owns its title; the inspector is reserved for the rest of the item's details. The page draws the
/// title and pinned properties above the note, so they scroll with it as one surface, and this carries out what
/// the person does there: the title is saved as the item's property, and each pin opens a native menu (the parent
/// pin opens the chooser directly while the item has no parent). Applied to the editor's view, whose container
/// the pins' frames arrive in.
struct ItemPageHeader: ViewModifier {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @AppStorage(InterfaceKey.textSize) private var interfaceTextSize = InterfaceStyle.defaultTextSize
    let item: Item
    let editor: EditorController
    let drafts: DetailsPresentation
    /// How far the editor's container reaches above the view's own frame: SwiftUI anchors a popover in the frame
    /// the safe area leaves, while the container runs up under the toolbar.
    let containerTop: CGFloat
    /// The parent pin's frame while its chooser is open.
    @State private var choosingParent: CGRect?

    func body(content: Content) -> some View {
        content
            .popover(isPresented: Binding { choosingParent != nil } set: { if !$0 { choosingParent = nil } },
                     attachmentAnchor: .rect(.rect((choosingParent ?? .zero).offsetBy(dx: 0, dy: -containerTop))), arrowEdge: .bottom) {
                if let parent = Self.parent(of: item.id, in: library) {
                    ItemRelationshipPicker(relationship: parent, candidates: library.relationshipCandidates(for: item.id, field: parent.field)) {
                        library.setItemRelationship(item.id, field: parent.field, targetIDs: $0, undoManager: undoManager)
                    }
                }
            }
            // The action may run on an earlier copy of this view, so it takes what changed from the change itself.
            .onChange(of: item.id, initial: true) { old, id in
                if old != id {
                    drafts.saveTitle(of: old, in: library, undoManager: undoManager)
                    // A refused status belongs to the visit, as the page showed it before.
                    drafts.draft(for: old, key: "status").rejected = false
                    if let parent = Self.parent(of: old, in: library) { drafts.draft(for: old, key: parent.field).rejected = false }
                    choosingParent = nil
                }
                editor.onHeaderEvent = handler
                let library = library, drafts = drafts
                editor.showHeader { Self.header(of: id, in: library, drafts: drafts) }
            }
            .onChange(of: interfaceTextSize) { editor.refreshHeader() }
            .onDisappear { drafts.saveTitle(of: item.id, in: library, undoManager: undoManager) }
    }

    /// What the page's header shows for the item, read from the library and the window's drafts as they are now.
    static func header(of id: ItemID, in library: any ItemLibrary, drafts: DetailsPresentation) -> PageHeader? {
        guard let item = library.item(id) else { return nil }
        let draft = drafts.draft(for: item.id, key: "title")
        let status = library.catalogue.itemTypes[item.type]?.statusField
        let parent = Self.parent(of: item.id, in: library)
        return PageHeader(
            item: item.id.rawValue,
            hidden: item.state == .trashed,
            title: item.title,
            draft: draft.isDirty ? draft.text : nil,
            titleRejected: draft.rejected,
            titleRefusal: library.titleRefusal,
            editable: library.canSetTitle(of: item),
            type: library.catalogue.itemTypes[item.type].map { Self.localized($0.label) },
            status: status.map { field in
                let value = Self.statusValue(of: item, in: field)
                // With nothing to pick from, the pin only shows the status the item has.
                return PageHeader.Pin(label: value.map { Self.localized(ItemTypeInfo.Field.label(ofOption: $0)) } ?? String(localized: "Status"),
                                      enabled: item.isEditable && field.isPicked, empty: value == nil, mark: .init(status: value))
            },
            parent: parent.map {
                // An item with no parent can only gain one, so the pin is idle where it cannot be edited.
                let title = $0.targets.first?.title
                return PageHeader.Pin(label: title ?? String(localized: "Parent"), enabled: title != nil || $0.isEditable,
                                      empty: title == nil, opensMenu: title != nil)
            },
            propertyRejected: drafts.draft(for: item.id, key: "status").rejected,
            parentRejected: parent.map { drafts.draft(for: item.id, key: $0.field).rejected } ?? false,
            interfaceTextSize: UserDefaults.standard.object(forKey: InterfaceKey.textSize) as? Int ?? InterfaceStyle.defaultTextSize
        )
    }

    /// Carries out what the page asks, for the item it names, which may be one the page has just left.
    private var handler: (PageHeaderEvent) -> Void {
        let library = library, drafts = drafts, undoManager = undoManager
        let choosingParent = $choosingParent
        // The editor keeps this, so it holds the editor weakly; otherwise neither would ever be released.
        return { [weak editor] event in
            guard let editor else { return }
            switch event {
            case .titleInput(let id, let text):
                let draft = drafts.draft(for: id, key: "title")
                draft.text = text
                draft.isDirty = true
                draft.rejected = false
            case .titleCommit(let id, let text, let startWriting):
                let draft = drafts.draft(for: id, key: "title")
                if text != (draft.isDirty ? draft.text : library.item(id)?.title) {
                    draft.text = text
                    draft.isDirty = true
                    draft.rejected = false
                }
                if drafts.saveTitle(of: id, in: library, undoManager: undoManager), startWriting {
                    editor.focus(id)
                }
            case .titleDiscard(let id):
                let draft = drafts.draft(for: id, key: "title")
                draft.isDirty = false
                draft.rejected = false
            case .menu(.status, let id, let rect):
                guard let item = library.item(id), let status = library.catalogue.itemTypes[item.type]?.statusField else { return }
                let menu = NSMenu()
                for choice in Self.statusChoices(of: item, in: status) {
                    let entry = actionItem(Self.localized(ItemTypeInfo.Field.label(ofOption: choice))) {
                        drafts.draft(for: id, key: status.key).rejected = !library.setItemProperty(id, key: status.key, value: .string(choice), undoManager: undoManager)
                    }
                    entry.state = Self.statusValue(of: item, in: status) == choice ? .on : .off
                    menu.addItem(entry)
                }
                editor.popUpMenu(menu, under: rect)
            case .menu(.parent, let id, let rect):
                guard let parent = Self.parent(of: id, in: library) else { return }
                guard let target = parent.targets.first else {
                    if parent.isEditable { choosingParent.wrappedValue = rect }
                    return
                }
                let menu = NSMenu()
                menu.autoenablesItems = false
                let open = actionItem(String(localized: "Open \(target.title)")) { [weak editor] in
                    if let id = target.itemID { editor?.onOpenNote(id) }
                }
                open.isEnabled = target.itemID.map { library.item($0) != nil } ?? false
                menu.addItem(open)
                let change = actionItem(String(localized: "Change Parent…")) { choosingParent.wrappedValue = rect }
                change.isEnabled = parent.isEditable
                menu.addItem(change)
                menu.addItem(.separator())
                let remove = actionItem(String(localized: "Remove Parent")) {
                    Self.removeParent(parent, of: id, in: library, drafts: drafts, undoManager: undoManager)
                }
                remove.isEnabled = parent.isEditable
                menu.addItem(remove)
                editor.popUpMenu(menu, under: rect)
            }
        }
    }

    /// Takes the item out of its parent. A library that refuses leaves the parent as it was, and the page says so
    /// until the next try or the next item.
    static func removeParent(
        _ parent: ItemRelationship, of id: ItemID, in library: any ItemLibrary, drafts: DetailsPresentation, undoManager: UndoManager?
    ) {
        drafts.draft(for: id, key: parent.field).rejected = !library.setItemRelationship(id, field: parent.field, targetIDs: [], undoManager: undoManager)
    }

    /// The status the item holds, if it holds one.
    static func statusValue(of item: Item, in field: ItemTypeInfo.Field) -> String? {
        item.value(of: field.key)?.string.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// What the status menu offers: the catalogue's values, and the item's own if it holds one the catalogue does
    /// not list, so the menu always shows what is set.
    static func statusChoices(of item: Item, in field: ItemTypeInfo.Field) -> [String] {
        let options = field.options
        guard let value = statusValue(of: item, in: field), !options.contains(value) else { return options }
        return options + [value]
    }

    private static func parent(of id: ItemID, in library: any ItemLibrary) -> ItemRelationship? {
        library.relationships(for: id).first { $0.field == "child-of" }
    }

    /// A catalogue's words, looked up in the String Catalog as SwiftUI's text would look them up.
    private static func localized(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }
}

/// Runs a menu item's action, for menus built for the page. The item holds it, since a target is not retained.
private final class MenuAction: NSObject {
    private let run: () -> Void

    init(_ run: @escaping () -> Void) { self.run = run }

    @objc func runAction() { run() }
}

private func actionItem(_ title: String, _ run: @escaping () -> Void) -> NSMenuItem {
    let action = MenuAction(run)
    let item = NSMenuItem(title: title, action: #selector(MenuAction.runAction), keyEquivalent: "")
    item.target = action
    item.representedObject = action
    return item
}
