import Foundation

/// The sidebar variants being compared, one value in the defaults. Nothing else knows how it is stored, so removing the
/// experiment is deleting this file and the places that read it.
nonisolated struct SidebarExperiment: Codable, Equatable, Sendable {
    /// Where a folding type row draws its chevron.
    enum ChevronPlace: String, Codable, CaseIterable, Sendable {
        /// At the trailing end, beside the count.
        case trailing
        /// Right after the name, the name giving way to it.
        case afterName
        /// In the gutter before the icon, where the system's own disclosure sits.
        case leading
    }

    /// What a click on a type that opens a list and also folds does.
    enum RowClick: String, Codable, CaseIterable, Sendable {
        /// The row opens its list; only the chevron folds.
        case opensOnly
        /// The row opens its list, and a click on the row already open folds or unfolds it.
        case opensThenFolds
    }

    static let key = "sidebarExperiment"

    var chevron = ChevronPlace.trailing
    var rowClick = RowClick.opensOnly
    /// The types whose list also shows the items of their subtypes, by type identifier.
    var stackedTypes: Set<String> = []

    init() {}

    private enum CodingKeys: String, CodingKey { case chevron, rowClick, stackedTypes }

    /// A value this build does not know reads as the default, so a stored experiment never stops the app reading.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        chevron = (try? values.decodeIfPresent(ChevronPlace.self, forKey: .chevron)).flatMap { $0 } ?? .trailing
        rowClick = (try? values.decodeIfPresent(RowClick.self, forKey: .rowClick)).flatMap { $0 } ?? .opensOnly
        stackedTypes = (try? values.decodeIfPresent(Set<String>.self, forKey: .stackedTypes)).flatMap { $0 } ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(chevron, forKey: .chevron)
        try values.encode(rowClick, forKey: .rowClick)
        try values.encode(stackedTypes.sorted(), forKey: .stackedTypes)
    }

    mutating func setStacked(_ type: String, _ isStacked: Bool) {
        if isStacked { stackedTypes.insert(type) } else { stackedTypes.remove(type) }
    }

    /// Whether a click on a row that opens and folds also folds it: only one on a row that was already open, so the
    /// click that selected the row is the one that opened it. A selection made as the press began, or a little
    /// before it, belongs to that press.
    func foldsOnClick(pressBegan: Date, selectedAt: Date?) -> Bool {
        guard rowClick == .opensThenFolds else { return false }
        guard let selectedAt else { return true }
        return selectedAt < pressBegan.addingTimeInterval(-Self.selectionSlack)
    }

    /// How long before a press's first event the list may already have selected the row it landed on.
    static let selectionSlack: TimeInterval = 0.15
}

/// The experiment as `@AppStorage` keeps it: its JSON.
nonisolated extension SidebarExperiment: RawRepresentable {
    var rawValue: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    init?(rawValue: String) {
        guard let value = try? JSONDecoder().decode(Self.self, from: Data(rawValue.utf8)) else { return nil }
        self = value
    }
}

nonisolated extension SidebarExperiment {
    static func stored(in defaults: UserDefaults = .standard) -> SidebarExperiment {
        defaults.string(forKey: key).flatMap(SidebarExperiment.init(rawValue:)) ?? SidebarExperiment()
    }

    static func update(in defaults: UserDefaults = .standard, _ change: (inout SidebarExperiment) -> Void) {
        var value = stored(in: defaults)
        change(&value)
        defaults.set(value.rawValue, forKey: key)
    }
}

extension ItemLibrary {
    /// The types below `type` that hold items of their own, which a list of the type alone leaves out.
    func subtypesHoldingItems(of type: String) -> [TypeID] {
        catalogue.descendants(of: TypeID(type))
            .filter { count(in: .itemType($0.rawValue)) > 0 }
            .sorted { $0.rawValue < $1.rawValue }
    }

    /// What opening a type lists with its subtypes' items too: the type's own place, which lists its own items only,
    /// and each subtype's place beside it.
    func items(inTypeAndSubtypes type: String) -> [Item] {
        let places = [TypeID(type)] + subtypesHoldingItems(of: type)
        return places.flatMap { items(in: .itemType($0.rawValue)) }
    }
}
