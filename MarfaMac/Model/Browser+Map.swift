import Foundation

// MARK: The map's choices

extension Browser {
    /// What the open place's map keeps: a saved view's choices in the app's settings, else the place's default view's.
    var mapChoices: MapChoices {
        (shown.savedView.map { macSettings(for: $0).map } ?? placeMaps[shown]) ?? MapChoices()
    }

    var mapStyle: ItemMapStyle { mapChoices.style ?? .standard }

    var groupsNearbyItems: Bool { mapChoices.groupsNearby ?? true }

    func setMapStyle(_ style: ItemMapStyle) {
        changeMap { $0.style = style == .standard ? nil : style }
    }

    func setGroupsNearbyItems(_ groups: Bool) {
        changeMap { $0.groupsNearby = groups ? nil : false }
    }

    /// Changes the map's choices. A saved view's are kept in the app's settings as they are made, and a place's in its
    /// default view. Undo takes either back.
    private func changeMap(_ change: (inout MapChoices) -> Void) {
        var choices = mapChoices
        change(&choices)
        let stored: MapChoices? = choices.isEmpty ? nil : choices
        if let id = shown.savedView {
            changeViewSettings(id) { $0.map = stored }
            return
        }
        setPlaceMap(stored, in: shown)
    }

    private func setPlaceMap(_ stored: MapChoices?, in place: PlaceView) {
        let before = placeMaps[place]
        guard stored != before else { return }
        placeMaps[place] = stored
        updatePlaceDefault(place) { $0.map = stored }
        registerUndo(String(localized: "Change Map")) { browser in
            guard browser.shown.isSame(place) else { return }
            browser.setPlaceMap(before, in: place)
        }
    }
}

extension Browser {
    /// Asks the map to show every marker. The map answers by watching `mapFitRequests`.
    func requestMapFit() {
        mapFitRequests += 1
    }
}

// MARK: Where the items stand

extension Browser {
    func mapPlacing(in library: any ItemLibrary) -> MapLayout.Placing? {
        let catalogue = library.catalogue
        return placed(mapWork, choice: catalogue, in: library) { items in
            MapLayout.placing(for: items, catalogue: catalogue)
        }
    }
}
