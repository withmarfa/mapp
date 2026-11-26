import AppKit
import SwiftUI

struct ItemDigest: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    var pane: FocusState<Browser.Pane?>.Binding
    @State private var cursor: ItemID?
    @State private var anchor: ItemID?
    @State private var keyboardTarget: ItemID?

    var body: some View {
        let choices = browser.digestChoices
        let current = browser.currentDigest
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let current {
                        ForEach(current.drawn(browser.listDrawn)) { part in
                            if part.startsSection, let group = part.group {
                                Text(group.title())
                                    .interfaceFont(.body.weight(.semibold))
                                    .accessibilityAddTraits(.isHeader)
                            }
                            ForEach(part.piles) { pile in
                                DigestPileView(
                                    pile: pile, choices: choices, browser: browser,
                                    isExpanded: browser.expandedDigestPiles.contains(pile.id),
                                    toggle: { browser.toggleDigestPile(pile) },
                                    choose: { id in
                                        keyboardTarget = nil
                                        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                                        select(id, extending: modifiers.contains(.shift), toggling: modifiers.contains(.command))
                                    })
                            }
                            if part.endsRun {
                                Color.clear.frame(height: 1).accessibilityHidden(true)
                                    .onAppear { browser.drawMoreOfList(after: part.run) }
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
                let ids = browser.digestOrder
                let selected = cursor.flatMap { current.shows($0, expanded: browser.expandedDigestPiles) ? $0 : nil }
                    ?? ids.first(where: browser.selection.contains)
                let offset = key.key == .upArrow ? -1 : 1
                guard let next = GallerySelection.moving(from: selected, among: ids, by: offset) else { return .ignored }
                select(next, extending: key.modifiers.contains(.shift), toggling: false)
                keyboardTarget = next
                return .handled
            }
            .onKeyPress(.return) { browser.openSelection() ? .handled : .ignored }
            .selectsAll { browser.selection = Set(browser.digestOrder) }
            .background {
                if let current {
                    DigestChosenCard(browser: browser, current: current, cursor: cursor, keyboardTarget: keyboardTarget, scroll: scroll)
                }
            }
        }
        .accessibilityIdentifier("ItemDigest")
        .accessibilityLabel(browser.pageTitle(in: library))
        .deletesChosen(browser) {
            guard let current else { return [] }
            return browser.selection.filter { current.shows($0, expanded: browser.expandedDigestPiles) }
        }
        .clearsSeveralOnEscape(browser)
        .quickLooksOnSpace(browser)
        .searchStatus(browser)
        .dragContainer(for: ItemReference.self) { ids in ids.map(library.dragReference(of:)) }
        .dragsSelection(of: browser)
        .onChange(of: browser.shown) {
            cursor = nil
            anchor = nil
            keyboardTarget = nil
        }
        .onChange(of: current?.id) {
            if let cursor, current?.positions[cursor] == nil { self.cursor = nil }
            if let anchor, current?.positions[anchor] == nil { self.anchor = nil }
        }
        .onChange(of: browser.expandedDigestPiles) {
            let selected = browser.selection.count == 1 ? browser.selection.first : nil
            if let cursor, current?.shows(cursor, expanded: browser.expandedDigestPiles) == false { self.cursor = selected }
            if let anchor, current?.shows(anchor, expanded: browser.expandedDigestPiles) == false { self.anchor = selected }
        }
        .overlay {
            if current == nil {
                PlaceProgress()
            } else if current?.sections.isEmpty == true {
                if browser.narrowsBySearch { SearchEmptyState(browser: browser) }
                else if browser.listHidesEveryGroup(in: library) { HiddenGroupsEmptyState() }
                else { PlaceEmptyState(browser: browser) }
            }
        }
        .overlay {
            if current != nil { FilteredEmptyState(browser: browser) }
        }
    }

    private func select(_ id: ItemID, extending: Bool, toggling: Bool) {
        browser.selection = extending || toggling
            ? GallerySelection.selecting(id, among: browser.digestOrder, current: browser.selection, anchor: anchor, extending: extending, toggling: toggling)
            : [id]
        if !extending || anchor == nil { anchor = id }
        cursor = id
        pane.wrappedValue = .list
    }
}

/// Scrolls after the page around a choice has been drawn, without making the card layout read the selection.
private struct DigestChosenCard: View {
    let browser: Browser
    let current: DigestLayout.Display
    let cursor: ItemID?
    let keyboardTarget: ItemID?
    let scroll: ScrollViewProxy

    var body: some View {
        let single = browser.selection.count == 1 ? browser.selection.first : nil
        let moving = keyboardTarget.flatMap { browser.selection.contains($0) ? $0 : nil }
        let target = single != nil && single != cursor ? single : moving
        let position = (target ?? single).flatMap { current.positions[$0] }
        let isDrawn = position.map { position in
            browser.listDrawn.runs(of: current.topItems.count).contains { $0.contains(position) }
        } ?? false
        Color.clear
            .onChange(of: position, initial: true) { if let position { browser.drawList(showing: position) } }
            .onChange(of: isDrawn ? target : nil, initial: true) { _, target in
                if let target { scroll.scrollTo(target) }
            }
    }
}

/// The layout still follows the copy while an item's full page takes its place.
struct DigestWatch: View {
    @CurrentLibrary private var library
    let browser: Browser
    @State private var daysSeen = 0

    var body: some View {
        let _ = daysSeen
        let next = browser.digestArrangement(in: library, now: library.now())
        let isPending = browser.searchResults(in: library)?.isPending == true
        Color.clear.frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .onClockChange { daysSeen += 1 }
            .onChange(of: next?.id, initial: true) {
                guard let next else { return }
                let previous = browser.currentDigest
                browser.digestDisplay = next
                if browser.selection.contains(where: { next.positions[$0] == nil }) {
                    let old = previous?.visibleIDs(expanded: browser.expandedDigestPiles) ?? []
                    browser.keepSelection(from: old, to: browser.digestOrder, isPending: isPending)
                } else if !isPending {
                    browser.keepHeldSelection(in: browser.digestOrder)
                }
            }
            .onChange(of: isPending) {
                if !isPending, next != nil { browser.keepHeldSelection(in: browser.digestOrder) }
            }
    }
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
        LazyVStack(alignment: .leading, spacing: 12) {
            DigestCard(
                item: pile.newest, choices: choices, browser: browser, choose: choose,
                more: moreLabel, isExpanded: isExpanded, toggle: toggle)
                .id(pile.newest.id)
            if isExpanded {
                ForEach(pile.earlier) { item in
                    DigestCard(item: item, choices: choices, browser: browser, choose: choose)
                        .id(item.id)
                        .padding(.leading, 18)
                }
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
        .accessibilityLabel(spoken(type: type, source: source, marked: marked))
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

    private var preview: String {
        let text = item.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        return text == item.displayTitle ? "" : text
    }

    private func spoken(type: String, source: String?, marked: Bool) -> Text {
        var parts = [item.displayTitle, type]
        if let source { parts.append(source) }
        if marked { parts.append(String(localized: "Feed")) }
        if !preview.isEmpty { parts.append(preview) }
        return Text(verbatim: parts.joined(separator: ", "))
    }

    private func metadata(icon: String?, type: String, source: String?, showsDate: Bool) -> some View {
        HStack(spacing: 7) {
            TonedGlyph(id: icon, size: 14)
            Text(type).foregroundStyle(.secondary).lineLimit(1)
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
        let isExcerpt = DigestLayout.Relationship(item)?.kind == .excerpt
        return VStack(alignment: .leading, spacing: 3) {
            (marked ? FeedMark.titled(title) : Text(title))
                .interfaceFont(.system(size: isExcerpt ? 16 : 15, weight: isExcerpt ? .medium : .semibold))
                .foregroundStyle(item.isUntitled ? .secondary : .primary)
            if !preview.isEmpty {
                Text(preview)
                    .interfaceFont(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .lineLimit(choices.lines)
            }
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
