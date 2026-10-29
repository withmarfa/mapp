import SwiftUI

/// The items the Add Tag sheet tags, with the undo manager of the window it was asked for in, since the sheet has
/// its own.
struct TagRequest: Identifiable {
    let id = UUID()
    let ids: Set<ItemID>
    let undoManager: UndoManager?
}

/// The field that takes a tag. It offers the tags already in the library as suggestions, and on Return gives the
/// text to `onAdd`. Where the library refuses the text, the field says why and keeps what was typed.
struct TagEntryField: View {
    @CurrentLibrary private var library
    @Binding var text: String
    /// The tags the item or items already hold, which are not suggested again.
    let held: [String]
    let identifier: String
    /// Whether the field is part of the inspector, which shows a placeholder in a light rounded field.
    var isInline = false
    /// Whether the field takes the keyboard when it appears, and what it tells when it gives it up.
    var takesFocus = false
    var onEnd: () -> Void = {}
    /// Why the last text was refused, which the caller clears when the text changes, and the field shows.
    @Binding var refusal: ItemTag.Refusal?
    let onAdd: (String) -> ItemTag.Refusal?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            field
            if let refusal {
                Text(refusal.message)
                    .interfaceFont(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(identifier)Refusal")
            }
        }
    }

    @ViewBuilder private var field: some View {
        let field = TextField("Add Tag", text: $text, prompt: Text(isInline ? "" : "Add Tag"))
            .labelsHidden()
            .focused($isFocused)
            .textInputSuggestions {
                ForEach(library.tagSuggestions(matching: text, excluding: held).prefix(8), id: \.self) { tag in
                    Text(tag).textInputCompletion(tag)
                }
            }
            .onSubmit(submit)
            .onChange(of: text) { refusal = nil }
            .accessibilityIdentifier(identifier)
        if isInline {
            field
                .textFieldStyle(.plain)
                .focusEffectDisabled()
                .frame(maxWidth: .infinity, alignment: .leading)
                // Drawn here and not as the field's prompt, whose colour differs from a menu's placeholder.
                .overlay(alignment: .leading) {
                    if text.isEmpty && !isFocused {
                        InspectorPlaceholder(text: "Add Tag").allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, InspectorMetrics.chipPadding / 2)
                .padding(.vertical, 3)
                .background(.quinary, in: .rect(cornerRadius: InspectorMetrics.chipRadius, style: .continuous))
                .task { if takesFocus { await Task.yield(); isFocused = true } }
                .onChange(of: isFocused) { if !isFocused { onEnd() } }
        } else {
            field.textFieldStyle(.roundedBorder)
        }
    }

    private func submit() {
        refusal = onAdd(text)
        if refusal == nil { text = "" }
    }
}

/// Adds tags to the items a window asked for.
struct TagSheet: View {
    @CurrentLibrary private var library
    @Environment(\.dismiss) private var dismiss
    let request: TagRequest
    @State private var text = ""
    @State private var refusal: ItemTag.Refusal?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Tag").interfaceFont(.title2.bold())
            Text(subtitle).foregroundStyle(.secondary)
            TagEntryField(text: $text, held: held, identifier: "TagSheetField", refusal: $refusal, onAdd: add)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { refusal = add(text) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(ItemTag.normalized(text).isEmpty)
                    .accessibilityIdentifier("TagSheetAdd")
            }
        }
        .padding(20)
        .frame(width: 360)
        // Items that are deleted elsewhere, or can no longer be changed, leave nothing to tag.
        .onChange(of: canTag) { if !canTag { dismiss() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("TagSheet")
    }

    private var items: [Item] { request.ids.compactMap { library.item($0) }.filter(\.canEditTags) }

    private var canTag: Bool { !items.isEmpty }

    /// The tags every one of the items holds, which are not suggested again.
    private var held: [String] {
        items.dropFirst().reduce(items.first?.tags ?? []) { $0.intersection($1.tags) }.sorted()
    }

    private var subtitle: String {
        if items.count == 1, let item = items.first {
            String(localized: "Add a tag to “\(item.title)”.")
        } else {
            String(localized: "Add a tag to \(items.count) items.")
        }
    }

    private func add(_ text: String) -> ItemTag.Refusal? {
        let refusal = library.addTag(text, to: request.ids, undoManager: request.undoManager)
        if refusal == nil { dismiss() }
        return refusal
    }
}

/// Opens the Add Tag sheet for the items, in the window whose presentation it is given.
struct AddTagButton: View {
    @CurrentLibrary private var library
    let ids: Set<ItemID>
    let details: DetailsPresentation?
    let undoManager: UndoManager?

    var body: some View {
        Button("Add Tag…", systemImage: "tag") {
            details?.tagRequest = TagRequest(ids: ids, undoManager: undoManager)
        }
        .disabled(details == nil || !library.canTag(ids))
    }
}

extension ItemLibrary {
    /// Whether any of the items can take a tag.
    func canTag(_ ids: Set<ItemID>) -> Bool {
        ids.contains { item($0)?.canEditTags == true }
    }
}

/// The inspector's Tags section: the item's tags, each with a button that removes it, and the field that the Tags
/// heading's plus opens. An item that can't be changed lists its tags with neither.
struct ItemTagsSection: View {
    let tags: [String]
    let isEditable: Bool
    /// What is typed and not added, kept by the window for the item; nil keeps it only while this is shown.
    var retainedDraft: ItemPropertyDraft?
    let onAdd: (String) -> ItemTag.Refusal?
    let onRemove: (String) -> Void
    @State private var localDraft = ItemPropertyDraft()
    @State private var refusal: ItemTag.Refusal?
    /// Whether the person has asked to add a tag, which opens the field until they leave it empty.
    @Binding var isAdding: Bool

    private var drafts: ItemPropertyDraft { retainedDraft ?? localDraft }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !tags.isEmpty {
                TagFlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        TagChip(tag: tag, onRemove: isEditable ? { onRemove(tag) } : nil)
                    }
                }
                .accessibilityIdentifier("ItemTags")
            }
            if isEditable {
                if isAdding || !drafts.text.isEmpty {
                    TagEntryField(text: Binding { drafts.text } set: { drafts.text = $0 },
                                  held: tags, identifier: "ItemTagField", isInline: true, takesFocus: isAdding,
                                  onEnd: { if drafts.text.isEmpty { isAdding = false } },
                                  refusal: $refusal, onAdd: onAdd)
                }
            }
        }
    }
}

/// One tag, with the button that removes it.
private struct TagChip: View {
    @Environment(\.interfaceTextSize) private var textSize
    let tag: String
    /// Nil for a tag that can't be removed.
    let onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9 * InterfaceStyle.scale(for: textSize), weight: .semibold))
                        .foregroundStyle(.secondary)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Remove Tag")
                .accessibilityLabel("Remove Tag \(tag)")
                .accessibilityIdentifier("ItemTagRemove.\(tag)")
            }
        }
        .interfaceFont(.body)
        .inspectorChip()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ItemTag.\(tag)")
    }
}

/// Rows of views that wrap to the width given, as a list of tags does. A view wider than the width takes a row to
/// itself, and is cut to it.
struct TagFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(in: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in rows(in: bounds.width, subviews: subviews) {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y), anchor: .topLeading,
                    proposal: ProposedViewSize(width: item.width, height: row.height))
            }
        }
    }

    private struct Row {
        var items: [(index: Int, x: CGFloat, width: CGFloat)] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(in width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        var y: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let itemWidth = min(size.width, width)
            if !row.items.isEmpty && row.width + spacing + itemWidth > width {
                rows.append(row)
                y += row.height + spacing
                row = Row(y: y)
            }
            row.y = y
            let x = row.items.isEmpty ? 0 : row.width + spacing
            row.items.append((index, x, itemWidth))
            row.width = x + itemWidth
            row.height = max(row.height, size.height)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
