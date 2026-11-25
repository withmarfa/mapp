import SwiftUI

/// What a row offers on itself while the pointer is over it, without a menu. Each acts through the calls the menus use
/// (`ItemLibrary.perform`, `deleteAfterSaving`), so a move here asks, toasts and undoes as it does there.
enum RowQuickAction: Hashable {
    case move(ItemMove)
    case delete

    var label: String {
        switch self {
        case .move(let move): move.name
        case .delete: String(localized: "Delete")
        }
    }

    var symbol: String {
        switch self {
        case .move(let move): move.symbol
        case .delete: "trash"
        }
    }
}

extension Browser {
    /// The actions the open place puts on the row under the pointer, where the View panel's Quick Actions has them on:
    /// Unarchive in the Archive, Keep in Library from the Feed, and Archive elsewhere, each with Delete.
    func quickActions(for item: Item) -> [RowQuickAction] {
        guard showsQuickActions, item.state != .trashed else { return [] }
        if listsArchive { return [.move(.unarchive), .delete] }
        let state: ItemMove = item.state == .archived ? .unarchive : .archive
        return (item.tier == .feed ? [.move(.keep)] : []) + [.move(state), .delete]
    }
}

/// The quick actions of one row: a capsule for a move, a round button for Delete.
struct RowQuickActions: View {
    let id: ItemID
    let actions: [RowQuickAction]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(actions, id: \.self) { action in
                RowQuickActionButton(id: id, action: action, onRow: true)
            }
        }
        .fixedSize()
    }
}

private struct RowQuickActionButton: View {
    @CurrentLibrary private var library
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    @Environment(\.undoManager) private var undoManager
    let id: ItemID
    let action: RowQuickAction
    let onRow: Bool

    var body: some View {
        if onRow {
            let showsLabel = action == .move(.keep) || action == .move(.unarchive)
            Button(action: perform) {
                if showsLabel {
                    Label(action == .move(.keep) ? String(localized: "Keep") : action.label, systemImage: action.symbol)
                } else {
                    Image(systemName: action.symbol)
                }
            }
                .appButton(.secondary, size: .small, icon: !showsLabel)
                .help(action.label)
                .accessibilityLabel(action.label)
                .accessibilityIdentifier("RowAction.\(action.label)")
        } else {
            Button(action.label, action: perform)
        }
    }

    private func perform() {
        switch action {
        case .move(let move):
            library.perform(move, on: [id], undoManager: undoManager, details: details)
        case .delete:
            library.deleteAfterSaving([id], undoManager: undoManager, asking: details)
        }
    }
}

extension View {
    func rowAccessibilityActions(for id: ItemID, actions: [RowQuickAction]) -> some View {
        accessibilityActions {
            ForEach(actions, id: \.self) { action in
                RowQuickActionButton(id: id, action: action, onRow: false)
            }
        }
    }

    func hoverQuickActions(for id: ItemID, actions: [RowQuickAction], alignment: Alignment = .trailing) -> some View {
        modifier(HoverQuickActions(id: id, actions: actions, alignment: alignment))
    }
}

private struct HoverQuickActions: ViewModifier {
    let id: ItemID
    let actions: [RowQuickAction]
    let alignment: Alignment
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                if isHovering, !actions.isEmpty {
                    RowQuickActions(id: id, actions: actions)
                        .padding(4)
                        .background(.regularMaterial, in: .capsule)
                        .accessibilityHidden(true)
                }
            }
            .onHover { isHovering = $0 }
            .rowAccessibilityActions(for: id, actions: actions)
    }
}
