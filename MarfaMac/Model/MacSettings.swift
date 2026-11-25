import Foundation

/// Every setting the app keeps in its defaults, named once. Settings > General > Reset This App's Settings clears exactly these, and
/// a launch of the sample library clears them for a clean start, so a setting added to the app is added here and to
/// `PreferencesMap` or it is missed by both. The copy of the library, its queue, the
/// sign-in and the connection are not settings, and a value set aside because it could not be read is kept for recovery.
enum MacSettings {
    /// The keys, one for each setting.
    static var keys: [String] {
        OrderKey.all + PageKey.all + ListKey.all + InterfaceKey.all + AppearanceKey.all
            + [
                DateFormat.key, WeekStart.key, StartWith.key, StartWith.lastPlaceKey, ReopenWindows.key, NewItemType.key,
                QuickAdd.lastTypeKey, RemotePictureSetting.key, Reporting.switchKey, UpdateSettings.betaKey, SidebarTypeRow.subtypeIconsKey,
                SourceViewMode.key, PlaceDensities.key, PlaceDefaults.key, ItemTableColumnLayouts.key, ViewLayouts.key,
                PagePlacements.key, PanelParts.key, ViewOrders.key, ListScope.defaultScopeKey, SidebarLayouts.defaultsKey, TypeLooks.defaultsKey, SearchLeaveOuts.defaultsKey,
                ShortcutBindings.defaultsKey, AnyAppShortcuts.defaultsKey, CalendarHourHeight.key,
                AutomaticExport.plansKey,
            ] + SearchOptions.keys
    }

    /// Puts every setting back to its default. Nothing else in the defaults is touched.
    static func reset(in defaults: UserDefaults = .standard) {
        for key in keys { defaults.removeObject(forKey: key) }
    }
}
