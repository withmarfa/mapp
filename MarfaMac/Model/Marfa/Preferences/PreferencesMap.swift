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

    /// How the setting's store reads one of its units' JSON text: the store's own decoder, so the sync never sends, and
    /// never writes here, a value the store cannot read (`PreferencesMap.reads`).
    struct Reader: Sendable {
        let reads: @Sendable (PreferenceUnit, String) -> Bool

        /// A value `Value` decodes.
        static func decoding<Value: Decodable>(_: Value.Type) -> Reader {
            Reader { _, text in (try? JSONDecoder().decode(Value.self, from: Data(text.utf8))) != nil }
        }

        /// A word that names a `Value`, as `@AppStorage` reads one.
        static func word<Value: RawRepresentable>(_: Value.Type) -> Reader where Value.RawValue == String {
            Reader { _, text in (PreferenceJSON.value(text) as? String).flatMap(Value.init(rawValue:)) != nil }
        }

        /// A value the defaults give back as `Value`.
        static func value<Value>(_: Value.Type) -> Reader {
            Reader { _, text in PreferenceJSON.value(text) is Value }
        }

        /// A switch or a number, which the defaults keep as a number.
        static let number = value(NSNumber.self)
        static let text = value(String.self)
    }

    let key: String
    let place: Place
    let reader: Reader

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

    /// The members' values this Mac could not read and the sync replaced, each as `{key: value}`, which no setting has a
    /// list of its own for. Kept for recovery: Reset, restore points and files leave it alone.
    nonisolated static let setAsideKey = "preferencesSetAside"

    private static func members(_ keys: [(String, SyncedSetting.Reader)], in field: PreferencesField) -> [SyncedSetting] {
        keys.map { SyncedSetting(key: $0.0, place: .member(field), reader: $0.1) }
    }

    /// Whether this Mac's store reads `text` as the value of `unit`. A member's `null` is no value, which every store reads.
    /// A row no setting here owns is the Marfa's, which this Mac never reads.
    static func reads(_ unit: PreferenceUnit, _ text: String) -> Bool {
        guard let value = PreferenceJSON.value(text), let setting = synced.first(where: { $0.owns(unit) }) else { return false }
        if case .member = unit, value is NSNull { return true }
        return setting.reader.reads(unit, text)
    }

    /// Each field holds the settings of one Settings page.
    /// Each with the reader of the type its store keeps it as.
    private static let members: [SyncedSetting] =
        members([
            (AppearanceKey.theme, .word(AppTheme.self)), (AppearanceKey.accent, .word(AccentChoice.self)),
            (AppearanceKey.highlights, .word(HighlightChoice.self)), (AppearanceKey.textFont, .text), (AppearanceKey.codeFont, .text),
            (AppearanceKey.typeChipTint, .word(TypeChipTint.self)), (AppearanceKey.sidebar, .word(SidebarColor.self)),
            (InterfaceKey.textSize, .number), (InterfaceKey.valuePanelStyle, .word(ValuePanelStyle.self)),
            (InterfaceKey.paletteMaterial, .word(PaletteMaterial.self)), (InterfaceKey.showsScrolledTitle, .number),
            (InterfaceKey.showsPageToolbarBackground, .number), (InterfaceKey.showsSidebarHistory, .number),
            (SidebarTypeRow.subtypeIconsKey, .number),
        ], in: .appearance)
        + members([
            (DateFormat.key, .word(DateFormat.self)), (WeekStart.key, .number), (StartWith.key, .word(StartWith.self)),
            (NewItemType.key, .text), (NewOpens.key, .word(NewOpens.self)), (ListKey.openItemsIn, .word(ItemOpening.self)),
            (RemotePictureSetting.key, .word(RemotePictureSetting.self)),
        ], in: .general)
        + members([
            (PageKey.fullWidth, .number), (PageKey.textSize, .number), (PageKey.checksSpelling, .number), (PageKey.readingWidth, .number),
            (PageKey.titleLines, .number), (PageKey.linkLook, .word(LinkLook.self)), (PageKey.showsCoordinates, .number),
            (PageKey.pinsProperties, .number), (LineSpacing.key, .word(LineSpacing.self)), (ParagraphSpacing.key, .word(ParagraphSpacing.self)),
            (IndentWith.key, .word(IndentWith.self)), (PasteAs.key, .word(PasteAs.self)), (EditingMode.key, .word(EditingMode.self)),
            (PageKey.smartPunctuation, .number), (PageKey.pairsBrackets, .number), (PageKey.continuesLists, .number),
            (PageKey.foldsHeadings, .number), (PageKey.showsCodeLineNumbers, .number), (PageKey.cornerShowsFormats, .number),
            (PageKey.cornerShowsTextSize, .number), (PageKey.cornerShowsFocus, .number), (SourceViewMode.key, .word(SourceViewMode.self)),
        ], in: .editor)
        + members([
            (ListKey.density, .word(Density.self)), (CalendarHourHeight.key, .number), (ListScope.defaultScopeKey, .word(ListScope.self)),
            (OrderKey.sort, .word(ItemSort.self)), (OrderKey.groupsByDate, .number),
        ], in: .lists)
        + members([
            (SearchOptions.includesArchivedKey, .number), (SearchOptions.includesFeedKey, .number),
            (SearchOptions.orderKey, .word(SearchOptions.Order.self)), (SearchOptions.showsSnippetsKey, .number),
        ], in: .search)
        + [SyncedSetting(
            key: SearchLeaveOuts.defaultsKey, place: .serverMember(.search, .data(SearchLeaveOuts.setAsideKey)),
            reader: .decoding(SearchLeaveOut.self))]

    private static let tables: [SyncedSetting] = [
        SyncedSetting(key: ShortcutBindings.defaultsKey, place: .rows(
            .commands, setting: "shortcut", .data, wrapper: "shortcuts", local: [], .data(ShortcutBindings.setAsideKey)),
            reader: .decoding(Shortcut?.self)),
        SyncedSetting(key: PagePlacements.key, place: .rows(
            .types, setting: "pagePlacements", .string, wrapper: nil, local: [], .string(PagePlacements.setAsideKey)),
            reader: .decoding(PagePlacements.Choice.self)),
        SyncedSetting(key: PanelParts.key, place: .rows(
            .types, setting: "panelPart", .string, wrapper: nil, local: [], .string(PanelParts.setAsideKey)),
            reader: SyncedSetting.Reader { _, text in PanelParts.reads(text) }),
        SyncedSetting(key: TypeLooks.defaultsKey, place: .serverRows(.types, setting: "look", .data(TypeLooks.setAsideKey)),
                      reader: .decoding(TypeLookChoice.self)),
        // A table's widths are kept with the view on this Mac alone.
        SyncedSetting(key: ViewLayouts.key, place: .rows(
            .views, setting: "viewLayout", .string, wrapper: nil, local: ["widths"], .string(ViewLayouts.setAsideKey)),
            reader: .decoding(ViewMacSettings.self)),
        SyncedSetting(key: PlaceDefaults.key, place: .rows(
            .places, setting: "placeDefaults", .data, wrapper: nil, local: [], .data(PlaceDefaults.setAsideKey)),
            reader: .decoding(PlaceDefault.self)),
        SyncedSetting(key: PlaceDensities.key, place: .rows(
            .places, setting: "placeDensity", .data, wrapper: nil, local: [], .data(PlaceDensities.setAsideKey)),
            reader: .word(Density.self)),
        SyncedSetting(key: ViewOrders.key, place: .rows(
            .places, setting: "viewOrder", .data, wrapper: nil, local: [], .data(ViewOrders.setAsideKey)),
            reader: .value([String].self)),
        SyncedSetting(key: ViewOrders.hiddenKey, place: .rows(
            .places, setting: "viewHidden", .data, wrapper: nil, local: [], .data(ViewOrders.hiddenSetAsideKey)),
            reader: .value(Bool.self)),
        SyncedSetting(key: SidebarLayouts.defaultsKey, place: .sidebar(.data(SidebarLayouts.setAsideKey)),
                      reader: SyncedSetting.Reader { unit, text in PreferencesSidebar.reads(unit, text) }),
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
        .commands, setting: "anyAppShortcut", .data, wrapper: nil, local: [], .data(AnyAppShortcuts.setAsideKey)),
        reader: .decoding(Shortcut.self))

    /// Every setting a settings file carries (`SettingsFile`).
    static let inFiles: [SyncedSetting] = synced + inFilesOnly

    /// The settings that stay on this Mac: window sizes and column widths, the right sidebar's width, where the
    /// last window was, what a new item last used (`NewItemRecents`), Reopen Windows (the Mac's own answer), consent to error reports, Export
    /// Automatically (which folder and when, for each Marfa), Beta Versions (Sparkle keeps its own keys, which are never
    /// synced either), a table's columns (mostly widths), and the shortcuts that work in any app (`inFilesOnly`).
    static let staysOnMac: [String] = [
        StartWith.lastPlaceKey, ReopenWindows.key, NewItemRecents.key, Reporting.switchKey, UpdateSettings.betaKey, ItemTableColumnLayouts.key,
        InterfaceKey.inspectorWidth, AnyAppShortcuts.defaultsKey, AutomaticExport.plansKey,
    ] + ColumnWidth.allCases.map(\.key)

    /// Every defaults key a synced setting reads or writes.
    static var syncedKeys: [String] { synced.flatMap(\.defaultsKeys) }
}
