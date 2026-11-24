import AppKit
import MarfaIcons
import SwiftUI

// The row of filters above a list, and the two panels it opens. Nothing here knows `Browser`: the row takes chips and
// actions, the panels take rows and actions, so the command palette's filter row can use them as they are. `FilterRow`
// is the adaptor that maps a window's filters onto them.

/// One filter as the row draws it: "Status is not Completed, Canceled".
struct FilterChipItem: Identifiable, Hashable {
    let id: String
    /// The field's name, drawn grey.
    var field: String
    /// "is" or "is not".
    var relation: String
    /// The values, joined; empty while the chip waits for its first value.
    var values: String
    /// Whether the chip says a value at all: "is set" says none, and a chip that waits for one shows an ellipsis.
    var needsValue = true
    /// A condition the row cannot change, such as a saved view's text search: shown so it is not hidden, and kept.
    var isLocked = false
    /// Why a locked chip is locked.
    var lockedReason: String?
}

/// Holds the views the panels open under, which the row's SwiftUI body cannot reach: one per chip, and the +.
@MainActor
final class FilterChipAnchors {
    static let addKey = "+"
    private var views: [String: Weak] = [:]

    private struct Weak { weak var view: NSView? }

    func view(for key: String) -> NSView? { views[key]?.view }

    fileprivate func set(_ view: NSView, for key: String) { views[key] = Weak(view: view) }

    /// Waits for SwiftUI to put a new chip in its window, then calls `open`. On timeout, `open` can clear the row's pending state.
    func whenShown(_ key: String, attempts: Int = 20, open: @escaping @MainActor () -> Void) {
        if view(for: key)?.window != nil || attempts == 0 {
            open()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(25)) { self.whenShown(key, attempts: attempts - 1, open: open) }
    }
}

/// A view laid behind a chip, for its panel to open under. It takes no clicks.
private struct FilterAnchor: NSViewRepresentable {
    let anchors: FilterChipAnchors
    let key: String

    func makeNSView(context: Context) -> NSView {
        let view = PassiveView()
        anchors.set(view, for: key)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { anchors.set(view, for: key) }

    private final class PassiveView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// The measures of the row, which the palette's filter row shares.
enum FilterChipMetrics {
    static let height: CGFloat = 26
    static let radius: CGFloat = 6
    static let widest: CGFloat = 300
    static let spacing: CGFloat = 6
}

/// The pop-up at the row's leading edge once it holds two filters: All or Any.
struct FilterMatchPicker {
    var isAny: Bool
    let choose: @MainActor (Bool) -> Void
}

/// The filters of a place as squared chips of one height, ending in a square +. A long row scrolls sideways, so it never
/// pushes the list off. The chips start at `leadingInset`, which a layout sets to its own left edge. Once the row holds two
/// filters a pop-up leads it (`matchPicker`); `trailingNote` ends the row, and `note` says under the chips what a view cannot keep.
struct FilterChipsBar: View {
    let chips: [FilterChipItem]
    var leadingInset: CGFloat = 12
    /// The palette shows no tooltips; a list's row does.
    var showsHelp = true
    var matchPicker: FilterMatchPicker?
    var trailingNote: String?
    var note: String?
    let anchors: FilterChipAnchors
    let open: (String) -> Void
    let remove: (String) -> Void
    let add: () -> Void
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: FilterChipMetrics.spacing) {
                if let matchPicker {
                    matchMenu(matchPicker, scale: scale)
                        .padding(.leading, leadingInset)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: FilterChipMetrics.spacing) {
                        ForEach(chips) { chip in
                            FilterChipView(chip: chip, scale: scale, open: { open(chip.id) }, remove: { remove(chip.id) })
                                .background { FilterAnchor(anchors: anchors, key: chip.id) }
                        }
                        Button(action: add) {
                            Image(systemName: "plus")
                                .font(.system(size: 11 * scale, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: FilterChipMetrics.height * scale, height: FilterChipMetrics.height * scale)
                                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: FilterChipMetrics.radius * scale, style: .continuous))
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .background { FilterAnchor(anchors: anchors, key: FilterChipAnchors.addKey) }
                        .help(showsHelp ? String(localized: "Add a filter") : "")
                        .accessibilityLabel("Add Filter")
                        .accessibilityIdentifier("FilterChipAdd")
                    }
                    .padding(.leading, matchPicker == nil ? leadingInset : 0)
                    .padding(.trailing, trailingNote == nil ? leadingInset : 0)
                }
                .scrollIndicators(.never)
                if let trailingNote {
                    Text(verbatim: trailingNote)
                        .font(.system(size: 11 * scale))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.trailing, leadingInset)
                        .fixedSize()
                        .accessibilityIdentifier("FilterRelativeNote")
                }
            }
            .padding(.vertical, 6)
            if let note {
                Text(verbatim: note)
                    .font(.system(size: 11 * scale))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, leadingInset)
                    .padding(.bottom, 6)
                    .accessibilityIdentifier("FilterRowNote")
            }
        }
        .accessibilityIdentifier("FilterChips")
    }

    private func matchMenu(_ picker: FilterMatchPicker, scale: CGFloat) -> some View {
        Menu {
            Picker("All of these", selection: Binding(get: { picker.isAny }, set: picker.choose)) {
                Text("All").tag(false)
                Text("Any").tag(true)
            }
            .pickerStyle(.inline)
        } label: {
            Text(picker.isAny ? "Any" : "All")
                .font(.system(size: 12 * scale))
                .frame(height: FilterChipMetrics.height * scale)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("All of these")
        .accessibilityIdentifier("FilterMatch")
    }
}

private struct FilterChipView: View {
    let chip: FilterChipItem
    let scale: CGFloat
    let open: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 4 * scale) {
            Button(action: open) {
                HStack(spacing: 4 * scale) {
                    Text(verbatim: chip.field).foregroundStyle(.secondary)
                    Text(verbatim: chip.relation)
                    if chip.needsValue || !chip.values.isEmpty {
                        Text(verbatim: chip.values.isEmpty ? "…" : chip.values).lineLimit(1).truncationMode(.tail)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(chip.isLocked)
            if chip.isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9 * scale))
                    .foregroundStyle(.tertiary)
                    .help(chip.lockedReason ?? "")
            } else {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.system(size: 8 * scale, weight: .bold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove Filter")
            }
        }
        .font(.system(size: 12 * scale))
        .padding(.horizontal, 8 * scale)
        .frame(height: FilterChipMetrics.height * scale)
        .frame(maxWidth: FilterChipMetrics.widest * scale)
        .background(.quaternary.opacity(chip.isLocked ? 0.35 : 0.6), in: .rect(cornerRadius: FilterChipMetrics.radius * scale, style: .continuous))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("FilterChip")
    }
}
