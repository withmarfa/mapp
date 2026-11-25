import AppKit
import SwiftUI

/// What the offers under the search field show and which one is chosen. A class, so the panel, which draws in a window of
/// its own, reads what the field changes.
@MainActor @Observable
final class SearchOffersModel {
    var offers: [SearchOffer] = []
    /// The offer the arrow keys are on; nil while none is, when Return searches as it did before.
    var highlighted: Int?
    var pick: (SearchOffer) -> Void = { _ in }
}

enum SearchOffersMetrics {
    static let rowHeight: CGFloat = 28
    static let inset: CGFloat = 5
    /// The line that names the filters, above the first.
    static let headingHeight: CGFloat = 24
    /// The rule above the last row, with the space round it.
    static let rule: CGFloat = 9
    static let width: ClosedRange<CGFloat> = 260...380

    /// Whether the list has filters to name: it does when any offer is a token.
    static func hasFilters(_ offers: [SearchOffer]) -> Bool { offers.contains { $0.kind != .text } }

    /// The height of the list for `offers`, at `scale` of the interface's text size.
    static func height(of offers: [SearchOffer], scale: CGFloat) -> CGFloat {
        let rows = CGFloat(offers.count) * rowHeight * scale
        let heading = hasFilters(offers) ? headingHeight * scale : 0
        return rows + heading + inset * 2 + (offers.count > 1 && offers.last?.kind == .text ? rule : 0)
    }
}

/// The menu of what typing in the search can make: under Filter, a token for each matching field and value, with the field
/// at the start of its row and the value at the end, then the words as the search. It is read by VoiceOver as a list, with
/// the row the arrow keys are on selected.
struct SearchOffersList: View {
    let model: SearchOffersModel
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        VStack(spacing: 0) {
            if SearchOffersMetrics.hasFilters(model.offers) {
                Text("Filter")
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: SearchOffersMetrics.headingHeight * scale, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(Array(model.offers.enumerated()), id: \.element.id) { index, offer in
                if offer.kind == .text, index > 0 {
                    Divider().padding(.vertical, 4)
                }
                row(offer, isChosen: model.highlighted == index)
                    .frame(height: SearchOffersMetrics.rowHeight * scale)
                    .contentShape(.rect)
                    .onTapGesture { model.pick(offer) }
            }
        }
        .padding(SearchOffersMetrics.inset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search Suggestions")
        .accessibilityIdentifier("ColumnSearchOffers")
    }

    /// Whether Return acts on this row: the one chosen, or the words as the search while none is.
    private func returnActs(_ offer: SearchOffer, isChosen: Bool) -> Bool {
        isChosen || (model.highlighted == nil && offer.kind == .text)
    }

    private func row(_ offer: SearchOffer, isChosen: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: offer.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            switch offer.kind {
            case .token:
                Text(offer.field)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 12)
                Text(offer.value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            case .text:
                Text(offer.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 12)
            }
            if returnActs(offer, isChosen: isChosen) {
                Image(systemName: "return")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(isChosen ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(offer.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .accessibilityIdentifier("ColumnSearchOffer")
    }
}

/// What the field's keys do to the offers: which is chosen, and whether they show. One for each field, held by it.
@MainActor
final class SearchOffersController {
    private let presenter = SearchOffersPresenter()
    private(set) var offers: [SearchOffer] = []
    private(set) var highlighted: Int?
    private var isFocused = false
    weak var field: NSView?
    var pick: (SearchOffer) -> Void = { _ in } {
        didSet { presenter.model.pick = { [weak self] in self?.pick($0) } }
    }

    /// The offer the arrow keys are on, nil while none is.
    var chosen: SearchOffer? { highlighted.flatMap { offers.indices.contains($0) ? offers[$0] : nil } }

    func setOffers(_ new: [SearchOffer]) {
        if new != offers {
            offers = new
            highlighted = nil
        }
        refresh()
    }

    func setFocused(_ focused: Bool) {
        isFocused = focused
        refresh()
    }

    func hide() {
        highlighted = nil
        presenter.hide()
    }

    /// Moves the choice one offer, from none to the first (or last, going up) and from the first back to none. Whether
    /// the key was used, so one with no offer to move to, or down from the last, is left to the field.
    func move(by step: Int) -> Bool {
        guard isFocused, !offers.isEmpty else { return false }
        if step > 0 {
            // Past the last offer the keyboard goes on to the list.
            if highlighted == offers.count - 1 {
                highlighted = nil
                refresh()
                return false
            }
            highlighted = highlighted.map { $0 + 1 } ?? 0
        } else {
            switch highlighted {
            case nil: highlighted = offers.count - 1
            case 0: highlighted = nil
            case let index?: highlighted = index - 1
            }
        }
        refresh()
        if let chosen, let field {
            NSAccessibility.post(
                element: field, notification: .announcementRequested,
                userInfo: [.announcement: chosen.title, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
        return true
    }

    private func refresh() {
        guard isFocused, !offers.isEmpty else { return hide() }
        presenter.update(offers: offers, highlighted: highlighted, under: field)
    }
}

/// A panel that never takes the keyboard, so the field above keeps its caret and its keys while the offers show.
private final class SearchOffersPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A click on a row acts at once, though the panel is not the window the keyboard is in.
private final class SearchOffersHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Shows the offers in a child window under the search field, the way a menu hangs from its button: it closes with the
/// field's focus, a resize or the app's leaving, and is never the keyboard's.
@MainActor
final class SearchOffersPresenter {
    let model = SearchOffersModel()
    private var panel: SearchOffersPanel?
    private weak var parent: NSWindow?
    private weak var anchor: NSView?
    private var observers: [NSObjectProtocol] = []
    private var appearanceWatch: NSKeyValueObservation?

    var isShown: Bool { panel != nil }

    isolated deinit { hide() }

    /// Shows `offers` under `anchor`, or puts the panel away where there are none.
    func update(offers: [SearchOffer], highlighted: Int?, under anchor: NSView?) {
        guard !offers.isEmpty, let anchor, anchor.window != nil else { return hide() }
        let changed = offers != model.offers
        model.offers = offers
        model.highlighted = highlighted
        self.anchor = anchor
        if panel == nil { open(under: anchor) } else if changed { layout() }
    }

    func hide() {
        guard let panel else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        appearanceWatch = nil
        self.panel = nil
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        model.offers = []
        model.highlighted = nil
    }

    private func open(under anchor: NSView) {
        guard let parent = anchor.window else { return }
        self.parent = parent
        let host = SearchOffersHost(rootView: SearchOffersList(model: model).interfaceTextStyle())
        host.sizingOptions = []
        let panel = SearchOffersPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.appearance = parent.effectiveAppearance
        panel.contentView = ValueEditPanelSession.surface(holding: host, style: ValuePanelStyle.stored(), appearance: panel.appearance)
        self.panel = panel
        layout()
        parent.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        let center = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.willCloseNotification, NSWindow.didEndLiveResizeNotification] {
            observers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            })
        }
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        })
        appearanceWatch = parent.observe(\.effectiveAppearance) { [weak self] window, _ in
            MainActor.assumeIsolated { self?.panel?.appearance = window.effectiveAppearance }
        }
    }

    private func layout() {
        guard let panel, let parent, let under = anchor?.screenRect(of: nil) else { return }
        let scale = InterfaceStyle.scale(for: UserDefaults.standard.object(forKey: InterfaceKey.textSize) as? Int ?? InterfaceStyle.defaultTextSize)
        let visible = ValueEditPanel.visibleArea(of: parent, around: under)
        let placement = ValuePanelFrame.placement(
            anchor: under, visible: visible, contentHeight: SearchOffersMetrics.height(of: model.offers, scale: scale),
            floor: SearchOffersMetrics.width.lowerBound * scale, ceiling: SearchOffersMetrics.width.upperBound * scale, gap: ValueEditMetrics.gap)
        if panel.frame != placement.frame {
            panel.setFrame(placement.frame, display: true)
            panel.invalidateShadow()
        }
        panel.contentView?.frame = NSRect(origin: .zero, size: placement.frame.size)
    }
}
