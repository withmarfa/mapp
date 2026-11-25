import Foundation

extension Browser {
    var currentDigest: DigestLayout.Display? {
        digestDisplay?.place == shown ? digestDisplay : nil
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
