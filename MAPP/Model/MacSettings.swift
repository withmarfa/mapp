import Foundation

/// Every setting MAPP keeps on this Mac, named once. Settings > General > Reset MAPP's Settings clears exactly these, and
/// a launch of the sample library clears them for a clean start, so a setting added to the app is added here and to
/// [Settings storage](../../docs/settings-storage.md) or it is missed by both. The copy of the library, its queue, the
/// sign-in and the connection are not settings, and a value set aside because it could not be read is kept for recovery.
enum MacSettings {
    /// The keys, one for each setting.
    static var keys: [String] {
        OrderKey.all + PageKey.all + ListKey.all + InterfaceKey.all + AppearanceKey.all
            + IndexPlace.allCases.flatMap { [$0.tabKey, $0.sortKey] }
            + [
                DateFormat.key, WeekStart.key, StartWith.key, StartWith.lastPlaceKey, ReopenWindows.key, NewItemType.key,
                QuickAdd.lastTypeKey, RemotePictureSetting.key, Reporting.switchKey, SidebarTypeRow.subtypeIconsKey,
                SourceViewMode.key, PlaceDensities.key, PlaceDefaults.key, ItemTableColumnLayouts.key, ViewLayouts.key,
                PagePlacements.key, IncludedSubtypes.key, SidebarLayouts.defaultsKey, TypeLooks.defaultsKey, SearchLeaveOuts.defaultsKey,
                ShortcutBindings.defaultsKey, AnyAppShortcuts.defaultsKey,
            ]
    }

    /// Settings kept one for each of a number of things, such as the open sections of each app's inspector.
    static let prefixes = ["\(InterfaceKey.inspectorAppOpen)."]

    /// Puts every setting back to its default. Nothing else in the defaults is touched.
    static func reset(in defaults: UserDefaults = .standard) {
        for key in keys { defaults.removeObject(forKey: key) }
        for key in defaults.dictionaryRepresentation().keys where prefixes.contains(where: key.hasPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
