import Foundation

extension Browser {
    /// Selection is set before the window applies the destination's layout.
    func opensInDigest(_ place: PlaceView) -> Bool {
        if let id = place.savedView { return (macSettings(for: id).layout ?? viewMode) == .digest }
        let layout = PlaceDefaults.stored(in: defaults).default(for: place)?.layout ?? naturalLayout(of: place)
        return layout == .digest
    }

    var currentDigest: DigestLayout.Display? {
        digestDisplay?.place == shown ? digestDisplay : nil
    }

    var digestOrder: [ItemID] {
        currentDigest?.visibleIDs(expanded: expandedDigestPiles) ?? []
    }

    /// An item reached through a link or restored selection remains the chosen item.
    func revealDigestSelection() {
        guard let digest = currentDigest, !digest.earlierMembers.isEmpty else { return }
        let piles = selection.compactMap { digest.earlierMembers[$0] }
        if !expandedDigestPiles.isSuperset(of: piles) { expandedDigestPiles.formUnion(piles) }
    }

    func toggleDigestPile(_ pile: DigestLayout.Pile) {
        if expandedDigestPiles.remove(pile.id) == nil {
            expandedDigestPiles.insert(pile.id)
        } else {
            let hidden = Set(pile.earlier.map(\.id))
            if !selection.isDisjoint(with: hidden) {
                selectAutomatically(selection.subtracting(hidden).union([pile.newest.id]))
            }
        }
    }

    var digestChoices: DigestChoices {
        if let id = shown.savedView { return macSettings(for: id).digest ?? DigestChoices() }
        return placeDigests[shown] ?? DigestChoices()
    }

    func changeDigest(_ change: (inout DigestChoices) -> Void) {
        if let id = shown.savedView {
            changeViewSettings(id) { $0.digest = Self.changedDigest($0.digest, change) }
        } else {
            setPlaceDigest(Self.changedDigest(placeDigests[shown], change), in: shown)
        }
    }

    private static func changedDigest(_ stored: DigestChoices?, _ change: (inout DigestChoices) -> Void) -> DigestChoices? {
        var choices = stored ?? DigestChoices()
        change(&choices)
        return choices == DigestChoices() ? nil : choices
    }

    private func setPlaceDigest(_ stored: DigestChoices?, in place: PlaceView) {
        let before = placeDigests[place]
        guard before != stored else { return }
        placeDigests[place] = stored
        updatePlaceDefault(place) { $0.digest = stored }
        registerUndo(String(localized: "Change View")) { browser in
            guard browser.shown.isSame(place) else { return }
            browser.setPlaceDigest(before, in: place)
        }
    }
}
