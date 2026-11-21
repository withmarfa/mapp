import SwiftUI

/// What a choice in a list part is: a name for a person, and an identifier the page keeps.
struct SettingsListEntry: Identifiable, Hashable {
    let id: String
    let title: String
}

/// A pop-up that chooses up to `limit` of its options, shown as their names joined with commas, in the order chosen. The
/// system's menu draws it, with a check beside each chosen option; once the limit is reached the others are dimmed, so a
/// choice is never dropped without being asked. It is 200 by 28 like every input, drawn as the system draws a menu button.
struct SettingsMultiPopUp: View {
    let title: LocalizedStringKey
    let options: [SettingsListEntry]
    @Binding var selection: [String]
    var limit = 2
    /// What it says while nothing is chosen.
    let emptyTitle: LocalizedStringKey

    private var names: [String] {
        selection.compactMap { id in options.first { $0.id == id }?.title }
    }

    var body: some View {
        Menu {
            ForEach(options) { option in
                let isOn = selection.contains(option.id)
                Toggle(option.title, isOn: Binding {
                    isOn
                } set: { on in
                    if on { selection.append(option.id) } else { selection.removeAll { $0 == option.id } }
                })
                .disabled(!isOn && selection.count >= limit)
            }
        } label: {
            HStack(spacing: 6) {
                if names.isEmpty {
                    Text(emptyTitle).foregroundStyle(SettingsTokens.secondaryText)
                } else {
                    Text(verbatim: names.joined(separator: ", "))
                }
                Spacer(minLength: 0)
                // The pop-ups beside it end in these two chevrons, which a menu button does not draw.
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .lineLimit(1)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.large)
        .buttonSizing(.flexible)
        .menuIndicator(.hidden)
        .frame(width: SettingsTokens.Metric.controlWidth, height: SettingsTokens.Metric.controlHeight)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(verbatim: names.joined(separator: ", ")))
    }
}

/// An ordered list changed in place, for a section's card (writing `entries` is how the page learns of a new order or a removal): each entry has a handle to drag it by and a menu that moves it
/// or takes it out, and the last row adds one from the options not yet in the list. A list that cannot take more is full:
/// its add row is dimmed and says why in `fullLine`.
struct SettingsOrderedList: View {
    @Binding var entries: [SettingsListEntry]
    /// What the add row offers: the choices not in the list.
    let candidates: [SettingsListEntry]
    let addTitle: LocalizedStringKey
    var isFull = false
    var onAdd: (SettingsListEntry) -> Void

    var body: some View {
        ForEach(entries) { entry in
            SettingsRow(verbatim: entry.title, lead: .symbol("line.3.horizontal"), size: .compact) {
                SettingsMoreMenu {
                    Button("Move Up") { move(entry, by: -1) }.disabled(entries.first?.id == entry.id)
                    Button("Move Down") { move(entry, by: 1) }.disabled(entries.last?.id == entry.id)
                    Divider()
                    Button("Remove", role: .destructive) { remove(entry) }
                }
            }
            .draggable(entry.id)
            .dropDestination(for: String.self) { dropped, _ in
                guard let from = dropped.first, from != entry.id else { return false }
                place(from, before: entry.id)
                return true
            }
        }
        addRow
    }

    @ViewBuilder private var addRow: some View {
        Menu {
            ForEach(candidates) { candidate in
                Button(candidate.title) { onAdd(candidate) }
            }
        } label: {
            SettingsRow(title: Text(addTitle), lead: .symbol("plus"), size: .compact, look: isFull || candidates.isEmpty ? .off : .normal)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(isFull || candidates.isEmpty)
        .containerValue(\.settingsRuleInset, SettingsTokens.Metric.textInset)
    }

    private func move(_ entry: SettingsListEntry, by step: Int) {
        guard let from = entries.firstIndex(of: entry), entries.indices.contains(from + step) else { return }
        var moved = entries
        moved.swapAt(from, from + step)
        entries = moved
    }

    private func remove(_ entry: SettingsListEntry) {
        entries.removeAll { $0 == entry }
    }

    private func place(_ id: String, before target: String) {
        guard let from = entries.firstIndex(where: { $0.id == id }), let to = entries.firstIndex(where: { $0.id == target }) else { return }
        var moved = entries
        moved.move(fromOffsets: [from], toOffset: from < to ? to + 1 : to)
        entries = moved
    }
}

/// What a page shows of the thing it sets, in a card of its own, with a rule between its rows: a few real rows or cards drawn
/// as the app draws them, so a choice is seen where it is made.
struct SettingsPreview<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        SettingsCard {
            content
                .padding(.horizontal, SettingsTokens.Metric.inset)
                .padding(.vertical, SettingsTokens.Metric.previewCardInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
    }
}
