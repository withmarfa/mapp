import AppKit
import SwiftUI

/// The page owns its title; the inspector is reserved for the rest of the item's details. The page draws the
/// title and chips above the note, so they scroll with it as one surface, and this carries out what the person
/// does there: the title is saved as the item's property, and each chip opens a native menu. Applied to the
/// editor's view, whose container the chips' frames arrive in.
struct ItemPageHeader: ViewModifier {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @AppStorage(InterfaceKey.textSize) private var interfaceTextSize = InterfaceStyle.defaultTextSize
    let item: Item
    let editor: EditorController
    let drafts: DetailsPresentation
    /// How far the editor's container reaches above the view's own frame: SwiftUI anchors a popover in the frame
    /// the safe area leaves, while the container runs up under the toolbar.
    let containerTop: CGFloat
    /// The parent chip's frame while its chooser is open.
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
        let status = Self.status(of: item, in: library)
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
            status: status.map { _ in
                PageHeader.Chip(label: (item.value(of: "status")?.string).map(ItemPropertyRow.choiceLabel) ?? String(localized: "Set Status"),
                                enabled: item.isEditable)
            },
            parent: parent.map { PageHeader.Chip(label: $0.targets.first?.title ?? String(localized: "Add Parent"), enabled: true) },
            propertyRejected: drafts.draft(for: item.id, key: "status").rejected,
            interfaceTextSize: UserDefaults.standard.object(forKey: InterfaceKey.textSize) as? Int ?? InterfaceStyle.defaultTextSize
        )
    }

    /// Carries out what the page asks, for the item it names, which may be one the page has just left.
    private var handler: (PageHeaderEvent) -> Void {
        let library = library, drafts = drafts, undoManager = undoManager, openWindow = openWindow
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
                guard let item = library.item(id), let status = Self.status(of: item, in: library),
                      case .choice(let choices) = status.kind else { return }
                let menu = NSMenu()
                for choice in choices {
                    let entry = actionItem(Self.localized(ItemPropertyRow.choiceLabel(choice))) {
                        drafts.draft(for: id, key: status.key).rejected = !library.setItemProperty(id, key: status.key, value: .string(choice), undoManager: undoManager)
                    }
                    entry.state = item.value(of: status.key)?.string == choice ? .on : .off
                    menu.addItem(entry)
                }
                editor.popUpMenu(menu, under: rect)
            case .menu(.parent, let id, let rect):
                guard let parent = Self.parent(of: id, in: library) else { return }
                let menu = NSMenu()
                menu.autoenablesItems = false
                if let target = parent.targets.first?.itemID, library.item(target) != nil {
                    menu.addItem(actionItem(String(localized: "Open Parent")) { openWindow(value: target) })
                }
                let choose = actionItem(parent.targets.isEmpty ? String(localized: "Choose Parent…") : String(localized: "Change Parent…")) {
                    choosingParent.wrappedValue = rect
                }
                choose.isEnabled = parent.isEditable
                menu.addItem(choose)
                editor.popUpMenu(menu, under: rect)
            }
        }
    }

    private static func status(of item: Item, in library: any ItemLibrary) -> ItemTypeInfo.Field? {
        guard let field = library.catalogue.itemTypes[item.type]?.fields.first(where: { $0.key == "status" }),
              case .choice = field.kind else { return nil }
        return field
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
