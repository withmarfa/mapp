import AppKit

/// The card under the pointer on a linked item of the page, and what the foot's Show More asks for.
extension EditorController {
    // MARK: Cards

    /// The pointer rests on a linked item of the page, in `rect` (the container's coordinates): the card of the item it
    /// names shows after a pause. A link in the text is asked of the core, which answers from the copy, so nothing is
    /// asked of the server.
    func hoverCard(on target: LinkCardTarget, in item: ItemID, rect: CGRect) {
        guard item == pageItemID, let library, let window = container.window else { return endHoverCard() }
        let anchor = LinkCardAnchor(rect: window.convertToScreen(container.convert(rect, to: nil)), window: window)
        LinkCardPresenter.shared.rest(library: library, at: anchor) { [weak self] in
            await self?.cardItem(of: target, from: item)
        }
    }

    func endHoverCard() { LinkCardPresenter.shared.end() }

    /// The item a card is for, or nil where the target names none: a link in the text that is missing or that more than
    /// one item answers to, or a page that has moved on.
    private func cardItem(of target: LinkCardTarget, from item: ItemID) async -> ItemID? {
        switch target {
        case .item(let id):
            return item == pageItemID ? id : nil
        case .wiki(let raw):
            guard let library, let answer = await library.linkAnswers(of: [raw], in: item)?.first, item == pageItemID,
                  answer.state == .bound else { return nil }
            return answer.item
        }
    }

    /// Show Card, from the menu over a linked item: the card shows now and VoiceOver is told what it says.
    func showCard(_ target: LinkCardTarget, rect: CGRect) {
        guard let library, let window = container.window, let item = pageItemID else { return }
        let anchor = LinkCardAnchor(rect: window.convertToScreen(container.convert(rect, to: nil)), window: window)
        Task { [weak self] in
            guard let id = await self?.cardItem(of: target, from: item) else { return NSSound.beep() }
            LinkCardPresenter.shared.show(id, library: library, at: anchor, announcing: true)
        }
    }

    /// The linked item the context menu opening now is over, heard from the page just before; each menu takes it once.
    func takeMenuCard() -> (target: LinkCardTarget, rect: CGRect)? {
        defer { menuCard = nil }
        return menuCard
    }

    // MARK: The foot

    /// How many rows each list at the foot of the item on the page shows, which the page asks for with Show More.
    var footLimits: PageFoot.Limits {
        guard let asked = footAsked, asked.item == heldItemID else { return [:] }
        return asked.limits
    }

    /// Show More under a foot list: the next `PageFoot.step` rows of the list with this key.
    func showMoreFoot(of item: ItemID, key: String) {
        guard item == pageItemID else { return }
        var limits = footAsked?.item == item ? footAsked?.limits ?? [:] : [:]
        limits[key] = (limits[key] ?? PageFoot.step) + PageFoot.step
        footAsked = (item, limits)
        refreshHeader()
    }
}
