import AppKit
import SwiftUI

struct ItemDigest: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    var pane: FocusState<Browser.Pane?>.Binding
    @State private var expanded: Set<DigestLayout.Pile.ID> = []
    @State private var cursor: ItemID?

    var body: some View {
        let choices = browser.digestChoices
        let current = browser.currentDigest
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let current {
                        ForEach(current.sections) { section in
                            if let group = section.group {
                                Text(group.title())
                                    .interfaceFont(.body.weight(.semibold))
                                    .accessibilityAddTraits(.isHeader)
                            }
                            ForEach(section.piles) { pile in
                                DigestPileView(
                                    pile: pile, choices: choices, browser: browser,
                                    isExpanded: expanded.contains(pile.id),
                                    toggle: { if expanded.remove(pile.id) == nil { expanded.insert(pile.id) } },
                                    choose: { select($0, extending: false, toggling: false, in: current) })
                            }
                        }
                    }
                }
                .frame(maxWidth: 660)
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 72)
                .frame(maxWidth: .infinity)
                .remembersScroll(in: browser.listMemory)
            }
            .topRowScrolls()
            .focusable()
            .focusEffectDisabled()
            .focused(pane, equals: .list)
            .onKeyPress(keys: [.upArrow, .downArrow], phases: .down) { key in
                guard let current else { return .ignored }
                let ids = visibleIDs(in: current)
                let selected = cursor ?? ids.first(where: browser.selection.contains)
                let offset = key.key == .upArrow ? -1 : 1
                guard let next = GallerySelection.moving(from: selected, among: ids, by: offset) else { return .ignored }
                select(next, extending: key.modifiers.contains(.shift), toggling: false, in: current)
                scroll.scrollTo(next)
                return .handled
            }
            .onKeyPress(.return) { browser.openSelection() ? .handled : .ignored }
            .selectsAll { if let current { browser.selection = Set(visibleIDs(in: current)) } }
        }
        .accessibilityIdentifier("ItemDigest")
        .accessibilityLabel(browser.pageTitle(in: library))
        .deletesChosen(browser) { Set(current.map(visibleIDs) ?? []) }
        .clearsSeveralOnEscape(browser)
        .quickLooksOnSpace(browser)
        .searchStatus(browser)
        .dragContainer(for: ItemReference.self) { ids in ids.map(library.dragReference(of:)) }
        .dragsSelection(of: browser)
        .onChange(of: browser.shown) {
            expanded.removeAll()
            cursor = nil
        }
        .onChange(of: cursor.map { current?.itemIDs.contains($0) == true }) { _, stillListed in
            if stillListed == false { cursor = nil }
        }
        .overlay {
            if let current, current.sections.isEmpty {
                if browser.narrowsBySearch { SearchEmptyState(browser: browser) }
                else if browser.listHidesEveryGroup(in: library) { HiddenGroupsEmptyState() }
                else { PlaceEmptyState(browser: browser) }
            }
        }
        .filteredEmptyState(browser)
    }

    private func visibleIDs(in layout: DigestLayout.Display) -> [ItemID] {
        guard !expanded.isEmpty else { return layout.topItems }
        return layout.sections.flatMap { section in
            section.piles.flatMap { pile in [pile.newest.id] + (expanded.contains(pile.id) ? pile.earlier.map(\.id) : []) }
        }
    }

    private func select(_ id: ItemID, extending: Bool, toggling: Bool, in layout: DigestLayout.Display) {
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        let shift = extending || modifiers.contains(.shift)
        let command = toggling || modifiers.contains(.command)
        browser.selection = shift || command
            ? GallerySelection.selecting(id, among: visibleIDs(in: layout), current: browser.selection, anchor: cursor, extending: shift, toggling: command)
            : [id]
        cursor = id
        pane.wrappedValue = .list
    }
}

/// The layout still follows the copy while an item's full page takes its place.
struct DigestWatch: View {
    @CurrentLibrary private var library
    let browser: Browser
    @State private var daysSeen = 0

    var body: some View {
        let _ = daysSeen
        let request = DigestRequest(
            key: browser.digestKey(in: library), stacking: browser.digestChoices.stacks,
            isPending: browser.searchResults(in: library)?.isPending == true)
        Color.clear.frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .onClockChange { daysSeen += 1 }
            .task(id: request) {
                guard let next = await browser.digestSections(in: library, stacking: request.stacking), !Task.isCancelled else { return }
                let previous = browser.currentDigest
                browser.digestDisplay = next
                if let previous, !browser.selection.isEmpty, !browser.selection.isSubset(of: next.itemIDs) {
                    browser.keepSelection(from: previous.itemOrder, to: next.itemOrder, isPending: request.isPending)
                } else if !request.isPending {
                    browser.keepHeldSelection(in: next.itemOrder)
                }
            }
    }
}

private struct DigestRequest: Equatable {
    let key: Browser.SectionsKey
    let stacking: Bool
    let isPending: Bool
}

private struct DigestPileView: View {
    @CurrentLibrary private var library
    let pile: DigestLayout.Pile
    let choices: DigestChoices
    let browser: Browser
    let isExpanded: Bool
    let toggle: () -> Void
    let choose: (ItemID) -> Void

    var body: some View {
        let more = moreLabel
        DigestCard(item: pile.newest, choices: choices, browser: browser, choose: choose, more: more, isExpanded: isExpanded, toggle: toggle)
            .id(pile.newest.id)
        if isExpanded {
            ForEach(pile.earlier) { item in
                DigestCard(item: item, choices: choices, browser: browser, choose: choose)
                    .id(item.id)
                    .padding(.leading, 18)
            }
        }
    }

    private var moreLabel: LocalizedStringKey? {
        let count = pile.earlier.count
        guard count > 0, case .relationship(let relationship) = pile.id else { return nil }
        switch relationship.kind {
        case .thread: return count == 1 ? "1 earlier message" : "\(count) earlier messages"
        case .excerpt:
            if let title = library.item(relationship.target)?.name { return "\(count) more from \(title)" }
            return count == 1 ? "1 earlier highlight" : "\(count) earlier highlights"
        }
    }
}

private struct DigestCard: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    @State private var isHovering = false
    let item: Item
    let choices: DigestChoices
    let browser: Browser
    let choose: (ItemID) -> Void
    var more: LocalizedStringKey?
    var isExpanded = false
    var toggle: (() -> Void)?

    private let shape = RoundedRectangle(cornerRadius: 14)
    private var isStacked: Bool { more != nil && !isExpanded }
    private var surface: some View {
        shape.fill(Color(nsColor: .textBackgroundColor))
            .overlay { shape.strokeBorder(.primary.opacity(0.10), lineWidth: 1) }
    }

    var body: some View {
        let icon = library.catalogue.icon(for: item.type)
        let type = library.catalogue.label(for: item.type)
        let source = item.source.map(library.sourceName)
        let marked = browser.listing.scope == .all && item.tier == .feed
        let actions = browser.quickActions(for: item)
        let selected = browser.selection.contains(item.id)
        VStack(alignment: .leading, spacing: 10) {
            Button { choose(item.id) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    metadata(icon: icon, type: type, source: source, showsDate: !isHovering || actions.isEmpty)
                    HStack(alignment: .top, spacing: 20) {
                        text(marked: marked)
                        if let picture = picture {
                            RowPictureView(picture: picture, icon: icon, size: CGSize(width: 132, height: 92), radius: 8)
                        }
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .simultaneousGesture(TapGesture(count: 2).onEnded { browser.open([item.id]) })
            if let more, let toggle {
                Button(action: toggle) {
                    Label {
                        Text(more)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .imageScale(.small)
                    }
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 24)
                    .background(.primary.opacity(0.04), in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 17)
        .background {
            ZStack {
                if isStacked {
                    surface.scaleEffect(0.985).rotationEffect(.degrees(reduceMotion ? 0 : 0.9)).offset(y: 11)
                    surface.rotationEffect(.degrees(reduceMotion ? 0 : -0.7)).offset(y: 6)
                }
                surface.shadow(color: .black.opacity(isHovering ? 0.10 : 0.03), radius: isHovering ? 9 : 1, y: 2)
            }
        }
        .overlay { if selected { shape.strokeBorder(.primary.opacity(0.28), lineWidth: 2).allowsHitTesting(false) } }
        .overlay(alignment: .topTrailing) {
            if isHovering, !actions.isEmpty {
                RowQuickActions(id: item.id, actions: actions)
                    .padding(.trailing, 18)
                    .padding(.top, 10)
            }
        }
        .contentShape(shape)
        .onHover { isHovering = $0 }
        .padding(.bottom, isStacked ? 10 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(marked ? Text("\(item.displayTitle), Feed") : Text(item.displayTitle))
        .accessibilityValue(more.map { Text($0) } ?? Text(verbatim: ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction { choose(item.id) }
        .accessibilityAction(named: Text("Open")) { browser.open([item.id]) }
        .accessibilityActions {
            if let toggle, more != nil {
                Button(isExpanded ? "Collapse Stack" : "Expand Stack", action: toggle)
            }
        }
        .rowAccessibilityActions(for: item.id, actions: actions)
        .contextMenu { ItemRowMenu(browser: browser, ids: selected ? browser.selection : [item.id], undoManager: undoManager) }
        .draggable(containerItemID: item.id)
    }

    private var picture: RowPicture? {
        guard choices.showsPictures else { return nil }
        let attachments = library.attachments(of: item.id).compactMap(library.item)
        return RowPicture.of(item, attachments: attachments)
    }

    private func metadata(icon: String?, type: String, source: String?, showsDate: Bool) -> some View {
        HStack(spacing: 7) {
            TonedGlyph(id: icon, size: 14)
            Text(type).foregroundStyle(.secondary)
            if let source { Text(source).foregroundStyle(.tertiary).lineLimit(1) }
            Spacer()
            if showsDate {
                Text(DateDisplay.text(of: item.occurred ?? item.created, place: .table, format: dateFormat, now: library.now()))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .interfaceFont(.caption)
        .frame(minHeight: 18)
    }

    private func text(marked: Bool) -> some View {
        let title = item.displayTitle
        let preview = item.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        let leadsWithExcerpt = DigestLayout.Relationship(item)?.kind == .excerpt && !preview.isEmpty
        return VStack(alignment: .leading, spacing: 3) {
            if !leadsWithExcerpt {
                (marked ? FeedMark.titled(title) : Text(title))
                    .interfaceFont(.system(size: 15, weight: .semibold))
                    .foregroundStyle(item.isUntitled ? .secondary : .primary)
            }
            if !preview.isEmpty, leadsWithExcerpt || preview != title {
                (leadsWithExcerpt && marked ? FeedMark.titled(preview) : Text(preview))
                    .interfaceFont(.system(size: leadsWithExcerpt ? 16 : 14, weight: leadsWithExcerpt ? .medium : .regular))
                    .foregroundStyle(leadsWithExcerpt ? .primary : .secondary)
                    .lineSpacing(4)
                    .lineLimit(choices.lines)
            }
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
