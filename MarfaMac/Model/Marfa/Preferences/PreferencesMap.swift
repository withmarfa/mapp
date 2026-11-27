import Foundation

/// Where each of this app's settings is kept in `app.marfa-mac.preferences`, named once, and the settings that stay on this Mac.
/// Every key in `MacSettings.keys` is in exactly one of the two lists, which `PreferencesMapTests` checks.
///
/// The defaults stay the store the app's code reads: they become this Mac's copy of the connected Marfa's settings, so
/// `@AppStorage` and the stores keep working and a launch reads nothing from the network.
nonisolated struct SyncedSetting: Sendable {
    /// How a stored value is kept in the defaults.
    enum Storage: Sendable { case data, string }

    /// The kind of list a store sets an unreadable value aside in, under its `...SetAside` key.
    enum SetAside: Sendable {
        case data(String)
        case string(String)
    }

    enum Place: Sendable {
        /// The whole value is one member of a field, named by its key.
        case member(PreferencesField)
        /// The connected server's entry of a value kept for each server is one member of a field, named by its key.
        case serverMember(PreferencesField, SetAside)
        /// A JSON object kept whole (inside `wrapper` where it has one) whose entries are rows, one for each of its keys.
        /// The members `local` names stay on this Mac and are kept from the row.
        case rows(PreferencesTable, setting: String, Storage, wrapper: String?, local: [String], SetAside)
        /// The connected server's entry of a value kept for each server, as `rows` splits a whole one.
        case serverRows(PreferencesTable, setting: String, SetAside)
        /// A JSON list of words, each a row whose value is `true`.
        case set(PreferencesTable, setting: String)
        /// The connected server's sidebar layout (`PreferencesSidebar`).
        case sidebar(SetAside)
    }

    let key: String
    let place: Place

    /// Where the setting's store sets aside a value it cannot read, where it has such a place.
    var setAsideKind: SetAside? {
        switch place {
        case .serverMember(_, let kind), .rows(_, _, _, _, _, let kind), .serverRows(_, _, let kind), .sidebar(let kind): kind
        case .member, .set: nil
        }
    }

    /// Whether the setting is kept for each server, so what this Mac holds of it belongs to the connected Marfa alone.
    var isPerServer: Bool {
        switch place {
        case .serverMember, .serverRows, .sidebar: true
        case .member, .rows, .set: false
        }
    }

    /// The defaults keys this setting reads and writes.
    var defaultsKeys: [String] { [key] }
}

enum PreferencesMap {
    static let synced: [SyncedSetting] = members + tables

    private static func members(_ keys: [String], in field: PreferencesField) -> [SyncedSetting] {
        keys.map { SyncedSetting(key: $0, place: .member(field)) }
    }

    /// A setting keeps its field when its control moves to another page.
    private static let members: [SyncedSetting] =
        members(AppearanceKey.all + [
            InterfaceKey.textSize, InterfaceKey.valuePanelStyle, InterfaceKey.paletteMaterial, InterfaceKey.showsScrolledTitle,
            InterfaceKey.showsPageToolbarBackground, InterfaceKey.showsSidebarHistory,
            SidebarTypeRow.subtypeIconsKey,
        ], in: .appearance)
        + members([
            DateFormat.key, WeekStart.key, StartWith.key, NewItemType.key, NewOpens.key, ListKey.openItemsIn, RemotePictureSetting.key,
        ], in: .general)
        + members(PageKey.all + [SourceViewMode.key], in: .editor)
        + members([ListKey.density, CalendarHourHeight.key, ListScope.defaultScopeKey] + OrderKey.all, in: .lists)
        + members(SearchOptions.keys, in: .search)
        + [SyncedSetting(key: SearchLeaveOuts.defaultsKey, place: .serverMember(.search, .data(SearchLeaveOuts.setAsideKey)))]

    private static let tables: [SyncedSetting] = [
        SyncedSetting(key: ShortcutBindings.defaultsKey, place: .rows(
            .commands, setting: "shortcut", .data, wrapper: "shortcuts", local: [], .data(ShortcutBindings.setAsideKey))),
        SyncedSetting(key: PagePlacements.key, place: .rows(
            .types, setting: "pagePlacements", .string, wrapper: nil, local: [], .string(PagePlacements.setAsideKey))),
        SyncedSetting(key: PanelParts.key, place: .rows(
            .types, setting: "panelPart", .string, wrapper: nil, local: [], .string(PanelParts.setAsideKey))),
        SyncedSetting(key: TypeLooks.defaultsKey, place: .serverRows(.types, setting: "look", .data(TypeLooks.setAsideKey))),
        // A table's widths are kept with the view on this Mac alone.
        SyncedSetting(key: ViewLayouts.key, place: .rows(
            .views, setting: "viewLayout", .string, wrapper: nil, local: ["widths"], .string(ViewLayouts.setAsideKey))),
        SyncedSetting(key: PlaceDefaults.key, place: .rows(
            .places, setting: "placeDefaults", .data, wrapper: nil, local: [], .data(PlaceDefaults.setAsideKey))),
        SyncedSetting(key: PlaceDensities.key, place: .rows(
            .places, setting: "placeDensity", .data, wrapper: nil, local: [], .data(PlaceDensities.setAsideKey))),
        SyncedSetting(key: ViewOrders.key, place: .rows(
            .places, setting: "viewOrder", .data, wrapper: nil, local: [], .data(ViewOrders.setAsideKey))),
        SyncedSetting(key: ViewOrders.hiddenKey, place: .rows(
            .places, setting: "viewHidden", .data, wrapper: nil, local: [], .data(ViewOrders.hiddenSetAsideKey))),
        SyncedSetting(key: SidebarLayouts.defaultsKey, place: .sidebar(.data(SidebarLayouts.setAsideKey))),
    ]

    /// Settings whose rows this Mac may lack only because it has not read them: an earlier copy kept another Mac's rows in
    /// the sync's record without storing them. A row of one that this Mac does not hold is never deleted from the Marfa;
    /// it is taken from there. Such a setting keeps a value for "not chosen" rather than removing its row.
    static let keptWhereAbsent: Set<String> = [ViewOrders.hiddenKey]

    /// Settings that stay on this Mac but that a settings file and a restore point carry, placed as they would be synced:
    /// the shortcuts that work in any app, since a system-wide shortcut can clash with an app one Mac alone has. Rows
    /// other Macs wrote under their place are left in the Marfa and owned by no setting the sync reads.
    static let inFilesOnly: [SyncedSetting] = [anyAppShortcuts]

    /// The shortcuts that work in any app, one row for each command, by the command's raw value.
    static let anyAppShortcuts = SyncedSetting(key: AnyAppShortcuts.defaultsKey, place: .rows(
        .commands, setting: "anyAppShortcut", .data, wrapper: nil, local: [], .data(AnyAppShortcuts.setAsideKey)))

    /// Every setting a settings file carries (`SettingsFile`).
    static let inFiles: [SyncedSetting] = synced + inFilesOnly

    /// The settings that stay on this Mac: window sizes and column widths, the right sidebar's and the page beside a layout's width, where the
    /// last window was, what a new item last used (`NewItemRecents`), where each audio and video item was left
    /// (`PlaybackPlaces`), Reopen Windows (the Mac's own answer), consent to error reports, Export
    /// Automatically (which folder and when, for each Marfa), Beta Versions (Sparkle keeps its own keys, which are never
    /// synced either), a table's columns (mostly widths), and the shortcuts that work in any app (`inFilesOnly`).
    static let staysOnMac: [String] = [
        StartWith.lastPlaceKey, ReopenWindows.key, NewItemRecents.key, PlaybackPlaces.key, Reporting.switchKey, UpdateSettings.betaKey, ItemTableColumnLayouts.key,
        InterfaceKey.inspectorWidth, InterfaceKey.besideWidth, AnyAppShortcuts.defaultsKey, AutomaticExport.plansKey,
    ] + ColumnWidth.allCases.map(\.key)

    /// Every defaults key a synced setting reads or writes.
    static var syncedKeys: [String] { synced.flatMap(\.defaultsKeys) }
}
