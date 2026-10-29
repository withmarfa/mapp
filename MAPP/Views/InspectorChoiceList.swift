import SwiftUI

/// The options of a choice property, listed in a popover. A pop-up menu is skipped by Tab unless the person turned
/// on full keyboard access, so a choice at rest is a focusable value that opens this list, which takes the arrow
/// keys, Return and Space itself and is dismissed by Escape.
struct InspectorChoiceList: View {
    struct Entry: Identifiable {
        /// The value written for the entry; empty for none.
        let id: String
        let label: LocalizedStringKey
    }

    let entries: [Entry]
    let selected: String
    /// Whether a last row, Other…, lets the person type a value of their own.
    var allowsOther = false
    let onPick: (String) -> Void
    let onOther: () -> Void
    @State private var highlighted: Int
    @FocusState private var isFocused: Bool

    init(entries: [Entry], selected: String, allowsOther: Bool = false, onPick: @escaping (String) -> Void, onOther: @escaping () -> Void) {
        self.entries = entries
        self.selected = selected
        self.allowsOther = allowsOther
        self.onPick = onPick
        self.onOther = onOther
        _highlighted = State(initialValue: entries.firstIndex { $0.id == selected } ?? 0)
    }

    private var rowCount: Int { entries.count + (allowsOther ? 1 : 0) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    row(index, checked: entry.id == selected) { Text(entry.label) }
                        .accessibilityIdentifier("ItemPropertyChoice.\(entry.id)")
                }
                if allowsOther {
                    Divider().padding(.vertical, 4)
                    row(entries.count, checked: false) { Text("Other…") }
                        .accessibilityIdentifier("ItemPropertyOther")
                }
            }
            .padding(6)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 200)
        .frame(maxHeight: 320)
        .interfaceFont(.callout)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(keys: [.upArrow, .downArrow, .return, .space], phases: .down) { press in
            switch press.key {
            case .upArrow: highlighted = max(highlighted - 1, 0)
            case .downArrow: highlighted = min(highlighted + 1, rowCount - 1)
            default: choose(highlighted)
            }
            return .handled
        }
        .accessibilityElement(children: .contain)
    }

    private func row<Label: View>(_ index: Int, checked: Bool, @ViewBuilder label: () -> Label) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .opacity(checked ? 1 : 0)
                .frame(width: 12)
                .accessibilityHidden(true)
            label().lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(highlighted == index ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: InspectorMetrics.rowRadius, style: .continuous))
        .contentShape(.rect)
        .onHover { if $0 { highlighted = index } }
        .onTapGesture { choose(index) }
        .accessibilityAddTraits(checked ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default) { choose(index) }
    }

    private func choose(_ index: Int) {
        if index < entries.count { onPick(entries[index].id) } else { onOther() }
    }
}
